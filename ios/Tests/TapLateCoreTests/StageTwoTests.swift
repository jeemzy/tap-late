import Foundation
import Testing
@testable import TapLateCore

@Test func shoppingAmountGoldenCases() throws {
    let text = "￥128.00 / 1 234,50 zł / USD 0 / €1.005,25 / $1,234.56"
    let amounts = PriceAmount.candidates(in: text)
    #expect(amounts.map(\.detected) == [.CNY, .PLN, .USD, .EUR, .USD])
    #expect(amounts.map(\.value) == ["128", "1234.50", "0", "1005.25", "1234.56"].map { Decimal(string: $0)! })
    for (text, expected) in [
        ("0 0.00 ¥0", ["0", "0", "0"]), ("1,234 1.234 12,50 12.50", ["1234", "1234", "12.50", "12.50"]),
        ("-12.50", ["-12.50"]), ("１２８．００元", ["128"]), ("1,23,45", []), ("1234567890123456789", [])
    ] {
        #expect(PriceAmount.candidates(in: text).map(\.value) == expected.map { Decimal(string: $0)! })
    }
    #expect(PriceAmount.candidates(in: "10 USD 20 EUR 30 PLN").map(\.text) == ["10 USD", "20 EUR", "30 PLN"])
    #expect(PriceAmount.candidates(in: "CN¥1 RMB2 3块 4元 US$5").map(\.detected) == [.CNY, .CNY, .CNY, .CNY, .USD])
    let rates = ExchangeRates(date: "2026-11-12", cny: 8, pln: 4, usd: Decimal(string: "1.1")!)
    #expect(try rates.values(for: 128, from: .CNY) == [.CNY: "128.00", .PLN: "64.00", .USD: "17.60", .EUR: "16.00"])
    for (amount, result) in [("1.005", "1.01"), ("-1.005", "-1.01"), ("0", "0.00")] {
        #expect(try rates.values(for: Decimal(string: amount)!, from: .EUR)[.EUR] == result)
    }
}

@Suite @MainActor struct HistoryAndChoiceTests {
    let image = CapturedImage(data: Data([1]), width: 200, height: 200)
    let start = Date(timeIntervalSince1970: 86_399)

    @Test func burstBoundariesAndExpiry() throws {
        var now = start
        let repository = MemoryRepository()
        let store = try SessionCoordinator(repository: repository, clock: { now })
        for offset in [0, 599, 1199, 1800] {
            now = start.addingTimeInterval(Double(offset))
            try store.capture(image)
        }
        #expect(store.groups.map { $0.sessions.count } == [1, 1, 2])
        let first = try #require(store.groups.last)
        try store.retry(first.sessions[0].id, configuration: .init(engine: .appleHighFidelity))
        now = first.newest.addingTimeInterval(86_399)
        let restored = try SessionCoordinator(repository: repository, clock: { now })
        restored.setActive(true)
        #expect(restored.groups.count == 3)
        restored.setActive(false)
        now = first.newest.addingTimeInterval(86_400)
        restored.setActive(true)
        #expect(restored.groups.count == 2)
        #expect(repository.images.count == 2)
        now = start.addingTimeInterval(1800 + 86_401)
        let expired = try SessionCoordinator(repository: repository, clock: { now })
        #expect(expired.sessions.isEmpty && repository.images.isEmpty)
    }

    @Test func deletingBridgeAndNewestKeepsBurstAndDeadline() throws {
        var now = start
        let repo = MemoryRepository()
        let store = try SessionCoordinator(repository: repo, clock: { now })
        let ids = try [0, 599, 1198].map { offset in
            now = start.addingTimeInterval(Double(offset))
            return try store.capture(image)
        }
        try store.deleteSession(ids[1])
        #expect(store.groups.count == 1)
        try store.deleteSession(ids[2])
        let restored = try SessionCoordinator(repository: repo, clock: { now })
        #expect(restored.groups.first?.newest == now)
        now.addTimeInterval(599)
        try restored.capture(image)
        #expect(restored.groups.count == 1)
    }

    @Test(arguments: [true, false]) func removingInFlightWorkRejectsLateResponse(expiry: Bool) async throws {
        var now = start
        let repo = MemoryRepository(), engine = FakeEngine()
        engine.holdAfterOne = true
        let store = try SessionCoordinator(repository: repo, engine: engine, clock: { now })
        let first = try store.capture(image)
        try store.capture(image)
        store.setActive(true)
        for _ in 0..<5000 where !engine.isHolding { await Task.yield() }
        try #require(engine.isHolding)
        if expiry {
            store.setActive(false)
            now.addTimeInterval(86_400)
            store.setActive(true)
        } else { try store.deleteGroup(try #require(store.groups.first?.id)) }
        let next = try store.capture(image)
        engine.releaseHeld()
        await store.waitUntilIdle()
        #expect(repo.records.map(\.id) == [next] && repo.images[first] == nil)
        #expect(store.sessions.first?.attempt.state == .ready)
    }

    @Test func repeatedChoicesSurviveReplacementOnlyForSameSource() async throws {
        let repo = MemoryRepository(), engine = FakeEngine()
        let source = "128 / 128"
        engine.regions = [TextRegion(id: "r", rawText: source, confidence: 1, rect: PixelRect(x: 0, y: 0, width: 80, height: 30))]
        let store = try SessionCoordinator(repository: repo, engine: engine)
        let id = try store.capture(image)
        store.setActive(true)
        await store.waitUntilIdle()
        let amounts = PriceAmount.candidates(in: source)
        #expect(amounts.allSatisfy { $0.detected == nil })
        try store.chooseCurrency(.PLN, sessionID: id, regionID: "r", source: source, amountID: amounts[0].id)
        try store.retry(id, configuration: .init(engine: .appleHighFidelity))
        try store.chooseCurrency(.USD, sessionID: id, regionID: "r", source: source, amountID: amounts[1].id)
        await store.waitUntilIdle()
        let restored = try SessionCoordinator(repository: repo)
        #expect(restored.sessions[0].currencyChoices["r"]?.currencies == [0: .PLN, 6: .USD])
        #expect(engine.configurationSnapshots.map(\.engine) == [.appleFast, .appleHighFidelity])
        #expect(engine.recognized == [id] && store.defaultConfiguration.engine == .appleFast)
        engine.correctedSource = "128 / 128 USD"
        try store.retry(id)
        await store.waitUntilIdle()
        #expect(store.sessions[0].currencyChoices.isEmpty)
        #expect(throws: (any Error).self) {
            try store.chooseCurrency(.EUR, sessionID: id, regionID: "r", source: source, amountID: 0)
        }
        let region = engine.regions[0]
        #expect(store.sessions[0].source(for: region) == engine.correctedSource)
        engine.correctedSource = ""
        try store.retry(id)
        await store.waitUntilIdle()
        #expect(store.sessions[0].source(for: region) == source)
        try store.deleteSession(id)
        #expect(repo.records.isEmpty && repo.images.isEmpty)
    }
}
