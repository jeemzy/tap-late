import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// ECB reference units per euro, dated by the publisher.
public struct ExchangeRates: Codable, Equatable, Sendable {
    public let date: String
    public let cny: Decimal
    public let pln: Decimal
    public let usd: Decimal
    public var eur: Decimal { 1 }
}

public enum RateError: Error { case invalidFeed }

private final class DailyRateParser: NSObject, XMLParserDelegate {
    private var depth = 0
    private var dailyDepth: Int?
    private var date: String?
    private var values: [String: Decimal] = [:]

    static func read(_ data: Data) throws -> ExchangeRates {
        guard data.count <= 128_000 else { throw RateError.invalidFeed }
        let parser = XMLParser(data: data)
        let delegate = DailyRateParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), parser.parserError == nil, let date = delegate.date,
              let cny = delegate.values["CNY"], let pln = delegate.values["PLN"],
              let usd = delegate.values["USD"] else { throw RateError.invalidFeed }
        return ExchangeRates(date: date, cny: cny, pln: pln, usd: usd)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String]) {
        depth += 1
        guard name == "Cube" else { return }
        if let day = attrs["time"] {
            let format = Date.ISO8601FormatStyle().year().month().day()
            guard date == nil, let parsed = try? format.parse(day),
                  format.format(parsed) == day else { parser.abortParsing(); return }
            date = day
            dailyDepth = depth
        } else if let dailyDepth, depth == dailyDepth + 1,
                  let code = attrs["currency"], ["CNY", "PLN", "USD"].contains(code) {
            guard values[code] == nil, let raw = attrs["rate"], raw.count <= 32,
                  raw.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let rate = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0, rate < 1_000_000 else { parser.abortParsing(); return }
            values[code] = rate
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if depth == dailyDepth { dailyDepth = nil }
        depth -= 1
    }
}

public actor ECBRateStore {
    private struct Cache: Codable {
        let checkedAt: Date
        let rates: ExchangeRates
    }

    private let file: URL
    private let fetch: @Sendable () async throws -> Data
    private var pending: Task<ExchangeRates, Error>?
    private var retryAfter = Date.distantPast

    init(file: URL, fetch: @escaping @Sendable () async throws -> Data) {
        self.file = file
        self.fetch = fetch
    }

    #if canImport(Darwin)
    public init(file: URL) {
        self.file = file
        self.fetch = {
            let url = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= 128_000 else { throw RateError.invalidFeed }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 128_000 else { throw RateError.invalidFeed }
                data.append(byte)
            }
            return data
        }
    }
    #endif

    public func snapshot(now: Date = .now) async throws -> ExchangeRates {
        if let pending { return try await pending.value }
        let cached = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: file))
        if let cached, now < max(cached.checkedAt.addingTimeInterval(3600), retryAfter) {
            return cached.rates
        }
        let task = Task {
            do {
                let fresh = try await DailyRateParser.read(fetch())
                let rates = cached.map { $0.rates.date > fresh.date ? $0.rates : fresh } ?? fresh
                let data = try JSONEncoder().encode(Cache(checkedAt: now, rates: rates))
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                return rates
            } catch {
                guard let cached else { throw error }
                retryAfter = now.addingTimeInterval(3600)
                return cached.rates
            }
        }
        pending = task
        defer { pending = nil }
        return try await task.value
    }
}
