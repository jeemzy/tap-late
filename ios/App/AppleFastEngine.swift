import Foundation
import ImageIO
import Translation
import UIKit
import Vision
import TapLateCore

@MainActor final class AppleFastEngine: ScreenshotEngine {
    private let repository: DeviceSessionRepository
    init(repository: DeviceSessionRepository) { self.repository = repository }

    func recognize(_ session: ScreenshotSession) async throws -> [TextRegion] {
        try await VisionRecognition.regions(url: repository.imageURL(session.id), width: session.width, height: session.height)
    }

    func translate(_ regions: [TextRegion], configuration: EngineConfiguration,
                   emit: @MainActor (String, RegionTranslation) throws -> Void) async throws {
        guard configuration.engine == .appleFast else { throw TranslationFailure.unavailable }
        var requests: [TranslationSession.Request] = []
        for region in regions {
            if region.rawText.range(of: "\\p{Han}", options: .regularExpression) == nil {
                try emit(region.id, RegionTranslation(source: region.rawText, translation: region.rawText))
            } else if let appearance = region.appearance, !appearance.colors.isEmpty {
                requests.append(.init(sourceText: FormattedTranslation.source(region.rawText, appearance: appearance),
                                      clientIdentifier: region.id))
            } else {
                requests.append(.init(sourceText: region.rawText, clientIdentifier: region.id))
            }
        }
        guard !requests.isEmpty else { return }
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: "en")
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        switch await availability.status(from: source, to: target) {
        case .installed: break
        case .supported: throw TranslationFailure.preparationRequired
        case .unsupported: throw TranslationFailure.unavailable
        @unknown default: throw TranslationFailure.unavailable
        }
        let session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        for try await response in session.translate(batch: requests) {
            try Task.checkCancellation()
            guard let id = response.clientIdentifier else { throw TranslationFailure.invalidResponse }
            let colors = FormattedTranslation.colors(in: response.attributedTargetText, matching: response.targetText)
            try emit(id, RegionTranslation(source: response.sourceText, translation: response.targetText, colors: colors))
        }
    }
}

enum FormattedTranslation {
    static func source(_ source: String, appearance: TextAppearance) -> AttributedString {
        var text = AttributedString(source)
        text.uiKit.foregroundColor = appearance.foreground.uiColor
        for span in appearance.colors {
            guard span.location >= 0, span.length > 0, span.location <= source.utf16.count,
                  span.length <= source.utf16.count - span.location,
                  let range = Range(NSRange(location: span.location, length: span.length), in: source),
                  let start = AttributedString.Index(range.lowerBound, within: text),
                  let end = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[start..<end].uiKit.foregroundColor = span.ink.uiColor
        }
        return text
    }

    static func colors(in target: AttributedString?, matching text: String) -> [TextColorSpan]? {
        guard let target, String(target.characters) == text else { return nil }
        var location = 0
        return target.runs.compactMap { run in
            let length = String(target[run.range].characters).utf16.count
            defer { location += length }
            guard let color = run.uiKit.foregroundColor, let ink = TextInk(color: color) else { return nil }
            return TextColorSpan(location: location, length: length, ink: ink)
        }
    }
}

private enum VisionRecognition {
    @concurrent static func regions(url: URL, width: Int, height: Int) async throws -> [TextRegion] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageImportError.invalid }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        let observations = (request.results ?? []).sorted { a, b in
            let rowA = Int((1 - a.boundingBox.midY) * 100)
            let rowB = Int((1 - b.boundingBox.midY) * 100)
            if rowA != rowB { return rowA < rowB }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return observations.enumerated().compactMap { index, observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let box = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
            let rect = pixelRect(box, width: width, height: height)
            return TextRegion(
                id: String(format: "r%03d", index + 1), rawText: candidate.string, confidence: Double(candidate.confidence),
                rect: PixelRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
                appearance: appearance(of: candidate, in: rect, image: image)
            )
        }
    }

    private static func pixelRect(_ box: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(x: box.minX * CGFloat(width), y: (1 - box.maxY) * CGFloat(height),
               width: box.width * CGFloat(width), height: box.height * CGFloat(height))
    }

    private static func appearance(of candidate: VNRecognizedText, in rect: CGRect, image: CGImage) -> TextAppearance? {
        guard let sample = ScreenshotInk.sample(image, in: rect) else { return nil }
        let base = TextAppearance(background: sample.background, foreground: sample.foreground)
        let text = candidate.string
        guard sample.hasMixedInk, (2...96).contains(text.count) else { return base }
        // Vision's accurate recognizer can return an entire word for one character.
        // Use estimated columns only for evenly spaced CJK lines where that box is too coarse.
        let cjk = text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }
        let columnWidth = rect.width / CGFloat(text.count)
        let evenlySpaced = cjk.count * 4 >= text.count * 3 && columnWidth >= rect.height * 0.55
            && columnWidth <= rect.height * 1.45
        var spans: [TextColorSpan] = []
        for (column, index) in text.indices.enumerated() where !text[index].isWhitespace {
            let next = text.index(after: index)
            let recognized = try? candidate.boundingBox(for: index..<next)
            var box = recognized.map { pixelRect($0.boundingBox, width: image.width, height: image.height) }
            if evenlySpaced, box == nil || (box?.width ?? 0) > columnWidth * 1.55 {
                box = CGRect(x: rect.minX + CGFloat(column) * columnWidth, y: rect.minY,
                             width: columnWidth, height: rect.height)
            }
            guard let box, box.width <= rect.height * 2.2,
                  let ink = ScreenshotInk.sample(image, in: box.intersection(rect), background: sample.background)?.foreground,
                  ink.distanceSquared(to: sample.foreground) >= 40 * 40 else { continue }

            let range = NSRange(index..<next, in: text)
            if let last = spans.last, last.location + last.length == range.location,
               last.ink.distanceSquared(to: ink) < 28 * 28 {
                spans[spans.count - 1] = TextColorSpan(location: last.location, length: last.length + range.length, ink: last.ink)
            } else {
                spans.append(TextColorSpan(location: range.location, length: range.length, ink: ink))
            }
        }
        return TextAppearance(background: sample.background, foreground: sample.foreground, colors: spans)
    }
}
