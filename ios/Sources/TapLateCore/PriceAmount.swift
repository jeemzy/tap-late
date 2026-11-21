import Foundation

public enum PriceCurrency: String, CaseIterable, Codable, Sendable {
    case CNY, PLN, USD, EUR

    public var name: String {
        switch self { case .CNY: "Yuan"; case .PLN: "Złoty"; case .USD: "Dollar"; case .EUR: "Euro" }
    }

    public var symbol: String {
        switch self { case .CNY: "¥"; case .PLN: "zł"; case .USD: "$"; case .EUR: "€" }
    }
}

public struct PriceAmount: Identifiable, Sendable {
    public let id: Int
    public let text: String
    public let value: Decimal
    public let detected: PriceCurrency?

    private static let number = try! NSRegularExpression(pattern: #"(?<![\d.,])[-+]?\d+(?:[.,]\d+)*(?:[ \u00a0\u202f]\d{3}(?!\d)(?:[.,]\d+)*)*"#)
    private static let marker = #"(CNY|RMB|CN¥|¥|元|块|PLN|zł|USD|US\$|\$|EUR|€)"#
    private static let prefix = try! NSRegularExpression(pattern: marker + #"\s*$"#, options: .caseInsensitive)
    private static let suffix = try! NSRegularExpression(pattern: #"^\s*"# + marker + #"(?![A-Za-z])"#, options: .caseInsensitive)

    public static func candidates(in source: String) -> [Self] {
        let text = source.precomposedStringWithCompatibilityMapping as NSString
        var consumed = 0
        return number.matches(in: text as String, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let raw = text.substring(with: match.range)
            guard let value = normalize(raw) else { return nil }
            let offset = match.range.location, end = NSMaxRange(match.range)
            let before = NSRange(location: consumed, length: offset - consumed)
            let after = NSRange(location: end, length: text.length - end)
            let leading = prefix.firstMatch(in: text as String, range: before)
            let trailing = leading == nil ? suffix.firstMatch(in: text as String, range: after) : nil
            let marker = (leading ?? trailing).map { text.substring(with: $0.range(at: 1)).uppercased() }
            let currency: PriceCurrency?
            switch marker {
            case "CNY", "RMB", "CN¥", "¥", "元", "块": currency = .CNY
            case "PLN", "ZŁ": currency = .PLN
            case "USD", "US$", "$": currency = .USD
            case "EUR", "€": currency = .EUR
            default: currency = nil
            }
            consumed = trailing.map { NSMaxRange($0.range) } ?? end
            let start = leading?.range.location ?? offset
            return Self(id: offset, text: text.substring(with: NSRange(location: start, length: consumed - start)),
                        value: value, detected: currency)
        }
    }

    private static func normalize(_ raw: String) -> Decimal? {
        var text = raw.filter { !$0.isWhitespace }.map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
        guard text.filter(\.isNumber).count <= 18 else { return nil }
        func grouped(_ whole: String, by separator: Character) -> Bool {
            let parts = whole.drop(while: { $0 == "-" || $0 == "+" }).split(separator: separator, omittingEmptySubsequences: false)
            return parts.count > 1 && (1...3).contains(parts[0].count) && parts.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
        }
        if let dot = text.lastIndex(of: "."), let comma = text.lastIndex(of: ",") {
            let index = max(dot, comma)
            let separator: Character = dot > comma ? "," : "."
            let whole = String(text[..<index])
            guard grouped(whole, by: separator), whole.filter({ $0 != separator }).drop(while: { $0 == "+" || $0 == "-" }).allSatisfy(\.isNumber) else { return nil }
            text = whole.filter { $0 != separator } + "." + text[text.index(after: index)...]
        } else {
            let separator: Character = text.contains(",") ? "," : "."
            if grouped(text, by: separator) { text.removeAll { $0 == separator } }
            else if text.filter({ $0 == separator }).count > 1 { return nil }
            else { text = text.replacingOccurrences(of: ",", with: ".") }
        }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}

public extension ExchangeRates {
    func values(for amount: Decimal, from source: PriceCurrency) throws -> [PriceCurrency: String] {
        func rate(_ code: PriceCurrency) -> Decimal {
            switch code { case .CNY: cny; case .PLN: pln; case .USD: usd; case .EUR: eur }
        }
        var result: [PriceCurrency: String] = [:]
        for code in PriceCurrency.allCases {
            var value = code == source ? amount : amount * rate(code) / rate(source)
            guard !value.isNaN else { throw RateError.invalidFeed }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 2, .plain)
            let string = NSDecimalString(&rounded, Locale(identifier: "en_US_POSIX"))
            let parts = string.components(separatedBy: ".")
            result[code] = parts[0] + "." + (parts.count == 1 ? "00" : parts[1].padding(toLength: 2, withPad: "0", startingAt: 0))
        }
        return result
    }
}

public struct RegionCurrencyChoices: Codable, Sendable {
    public let source: String
    public var currencies: [Int: PriceCurrency]
}
