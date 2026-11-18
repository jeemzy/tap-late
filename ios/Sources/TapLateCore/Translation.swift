import Foundation

public enum EngineKind: String, Codable, Sendable, CaseIterable {
    case appleFast, appleHighFidelity, foundationModel, openAI
}

public struct EngineConfiguration: Codable, Sendable, Equatable {
    public var engine: EngineKind
    public var model: String?
    public var reasoning: String?
    public init(engine: EngineKind = .appleFast, model: String? = nil, reasoning: String? = nil) {
        self.engine = engine
        self.model = model
        self.reasoning = reasoning
    }
}

public struct PixelRect: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct TextInk: Codable, Sendable, Equatable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// An ink color on a UTF-16 range of the accompanying source or target text.
public struct TextColorSpan: Codable, Sendable, Equatable {
    public let location: Int
    public let length: Int
    public let ink: TextInk

    public init(location: Int, length: Int, ink: TextInk) {
        self.location = location
        self.length = length
        self.ink = ink
    }
}

public struct TextAppearance: Codable, Sendable, Equatable {
    public let background: TextInk
    public let foreground: TextInk
    public let colors: [TextColorSpan]

    public init(background: TextInk, foreground: TextInk, colors: [TextColorSpan] = []) {
        self.background = background
        self.foreground = foreground
        self.colors = colors
    }
}

public struct TextRegion: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let rawText: String
    public let confidence: Double
    public let rect: PixelRect
    public let appearance: TextAppearance?
    public init(id: String, rawText: String, confidence: Double, rect: PixelRect, appearance: TextAppearance? = nil) {
        self.id = id; self.rawText = rawText; self.confidence = confidence; self.rect = rect
        self.appearance = appearance
    }
}

public enum RegionOutcome: String, Codable, Sendable { case translated, unreadable }

public struct RegionTranslation: Codable, Sendable, Equatable {
    public let source: String?
    public let translation: String?
    public let outcome: RegionOutcome
    public let colors: [TextColorSpan]?
    public init(source: String?, translation: String?, outcome: RegionOutcome? = nil, colors: [TextColorSpan]? = nil) {
        self.source = source; self.translation = translation
        self.outcome = outcome ?? (translation == nil ? .unreadable : .translated)
        self.colors = colors
    }
    private enum CodingKeys: String, CodingKey { case source, translation, outcome, colors }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        translation = try values.decodeIfPresent(String.self, forKey: .translation)
        outcome = try values.decodeIfPresent(RegionOutcome.self, forKey: .outcome) ?? (translation == nil ? .unreadable : .translated)
        colors = try values.decodeIfPresent([TextColorSpan].self, forKey: .colors)
    }
}

public enum ProcessingState: String, Codable, Sendable {
    case queued, recognizing, translating, needsPreparation, needsReview, failed, ready
}

public struct TranslationAttempt: Identifiable, Codable, Sendable {
    public let id: UUID
    public let configuration: EngineConfiguration
    public let order: Int
    public var state: ProcessingState = .queued
    public var results: [String: RegionTranslation] = [:]
    public var error: String?

    public init(configuration: EngineConfiguration, order: Int) {
        id = UUID(); self.configuration = configuration; self.order = order
    }
}

@MainActor public protocol ScreenshotEngine {
    func recognize(_ session: ScreenshotSession) async throws -> [TextRegion]
    func translate(_ regions: [TextRegion], configuration: EngineConfiguration,
                   emit: @MainActor (String, RegionTranslation) throws -> Void) async throws
}

public enum TranslationFailure: LocalizedError {
    case preparationRequired, unavailable, invalidRegions, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .preparationRequired: "Download the Chinese and English translation languages, then retry."
        case .unavailable: "This engine is unavailable in this build. Choose Apple Fast or retry when it is available."
        case .invalidRegions: "Some text regions could not be read safely. Choose the screenshot again."
        case .invalidResponse: "Some regions were not translated. Retry the unfinished regions."
        }
    }
}
