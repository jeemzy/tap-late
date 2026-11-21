import Foundation
import Testing
@testable import TapLateCore

private func feed(_ day: String, _ cny: String = "8.01") -> Data {
    Data("""
    <Envelope><Cube><Cube time="\(day)"><Cube currency="CNY" rate="\(cny)"/>
    <Cube currency="PLN" rate="4.25"/><Cube currency="USD" rate="1.09"/></Cube></Cube></Envelope>
    """.utf8)
}

@Test func datedRatesSurviveRestartOfflineAndOlderFeed() async throws {
    let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let store = ECBRateStore(file: file) { feed("2026-11-20") }
    let first = try await store.snapshot(now: start)
    #expect(first.date == "2026-11-20")
    #expect(first.cny == Decimal(string: "8.01"))
    #expect(first.eur == 1)
    let next = ECBRateStore(file: file) { feed("2026-11-23", "8.15") }
    #expect(try await next.snapshot(now: start.addingTimeInterval(3599)) == first)
    let refreshed = try await next.snapshot(now: start.addingTimeInterval(3600))
    #expect(refreshed.date == "2026-11-23")
    #expect(refreshed.cny == Decimal(string: "8.15"))
    let old = ECBRateStore(file: file) { feed("2026-11-20") }
    #expect(try await old.snapshot(now: start.addingTimeInterval(7200)) == refreshed)
    let offline = ECBRateStore(file: file) { throw URLError(.notConnectedToInternet) }
    #expect(try await offline.snapshot(now: start.addingTimeInterval(365 * 86400)) == refreshed)
}

@Test func malformedRatesCannotCreateAnOfflineCache() async throws {
    let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let invalid = [feed("2026-11-32"), feed("2026-11-20", "8garbage"),
                   feed("2026-11-20", "0"), Data("<Cube/>".utf8), Data(repeating: 32, count: 128_001)]
    for data in invalid {
        let store = ECBRateStore(file: file) { data }
        await #expect(throws: RateError.self) { try await store.snapshot() }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
