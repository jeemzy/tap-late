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

public struct TextRegion: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let rawText: String
    public let confidence: Double
    public let rect: PixelRect
    public init(id: String, rawText: String, confidence: Double, rect: PixelRect) {
        self.id = id; self.rawText = rawText; self.confidence = confidence; self.rect = rect
    }
}

public struct RegionTranslation: Codable, Sendable, Equatable {
    public let source: String?
    public let translation: String?
    public init(source: String?, translation: String?) {
        self.source = source; self.translation = translation
    }
}

public enum ProcessingState: String, Codable, Sendable {
    case queued, recognizing, translating, needsPreparation, failed, ready
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
