import Foundation
import Translation
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
        let session = try TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        for try await response in session.translate(batch: requests) {
            try Task.checkCancellation()
            guard let id = response.clientIdentifier else { throw TranslationFailure.invalidResponse }
            try emit(id, RegionTranslation(source: response.sourceText, translation: response.targetText))
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
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        try Task.checkCancellation()
        let observations = (request.results ?? []).sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.012 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return observations.enumerated().compactMap { index, observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let box = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
            return TextRegion(
                id: String(format: "r%03d", index + 1), rawText: candidate.string, confidence: Double(candidate.confidence),
                rect: PixelRect(x: box.minX * Double(width), y: (1 - box.maxY) * Double(height),
                                width: box.width * Double(width), height: box.height * Double(height))
            )
        }
    }
}
