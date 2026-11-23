import XCTest
import UIKit

@MainActor final class ViewerTests: XCTestCase {
    func testLiveReadingScopeAndEngineAreRemembered() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["live-translation"].tap()
        app.buttons["live-zone"].tap()
        app.segmentedControls.buttons["Middle"].tap()
        app.buttons["live-whole"].tap()
        XCTAssertFalse(app.segmentedControls.buttons["Middle"].exists)
        app.buttons["live-engine"].tap()
        app.buttons["Apple High Fidelity"].tap()
        goBack(app)
        app.buttons["live-translation"].tap()
        XCTAssertTrue(app.buttons["live-whole"].isSelected)
        XCTAssertTrue(app.buttons["start-live"].isEnabled)
        XCTAssertTrue(app.buttons["live-engine"].label.contains("Apple High Fidelity") ||
                      (app.buttons["live-engine"].value as? String) == "Apple High Fidelity")
        #if targetEnvironment(simulator)
        app.buttons["start-live"].tap()
        XCTAssertTrue(app.staticTexts["Live screen sharing requires a physical iPhone."].waitForExistence(timeout: 5))
        #endif
    }

    func testSecondImportReplacesVisibleScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--warm-capture"]
        app.launch()
        let region = app.buttons["region-r001"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        let firstTranslation = expectation(for: NSPredicate(format: "label CONTAINS %@", "Blue · premium"), evaluatedWith: region)
        wait(for: [firstTranslation], timeout: 10)
        let originalWidth = region.frame.width
        XCTAssertLessThan(try redPixelFraction(app.screenshot()), 0.02)
        app.scrollViews["screenshot-canvas"].pinch(withScale: 2, velocity: 1)
        region.tap()
        XCTAssertTrue(app.buttons["close-details"].waitForExistence(timeout: 5))
        app.buttons["toggle-original"].tap()
        app.buttons["More"].tap()
        app.buttons["Submit second screenshot"].tap()

        let secondTranslation = expectation(for: NSPredicate(format: "label == %@", "红色, Red"), evaluatedWith: region)
        wait(for: [secondTranslation], timeout: 20)
        XCTAssertEqual(app.buttons["toggle-original"].label, "Show original")
        XCTAssertFalse(app.buttons["close-details"].exists)
        XCTAssertEqual(region.frame.width, originalWidth, accuracy: 3)
        XCTAssertGreaterThan(try redPixelFraction(app.screenshot()), 0.08)
        region.tap()
        XCTAssertEqual(app.staticTexts["detail-translation"].label, "Red")
        goBack(app)
        XCTAssertTrue(app.descendants(matching: .any)["open-last-screenshot"].waitForExistence(timeout: 5))
    }

    // B has a solid red panel covering about a fifth of its image; A has none.
    private func redPixelFraction(_ screenshot: XCUIScreenshot) throws -> Double {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let source = try XCTUnwrap(screenshot.image.cgImage)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: size, height: size,
                                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        let red = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] < 65 && pixels[$0 + 2] < 65
        }
        return Double(red.count) / Double(size * size)
    }

    func testSelectToggleAndRevealBottomRegion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let region = app.buttons["region-r001"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        region.tap()
        let translation = app.staticTexts["detail-translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        XCTAssertEqual(translation.label, "Blue · premium")
        app.buttons["toggle-original"].tap()
        XCTAssertEqual(app.buttons["toggle-original"].label, "Show translations")
        app.buttons["toggle-original"].tap()
        app.buttons["close-details"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "details-island").firstMatch.exists)
        let bottom = app.buttons["region-r003"]
        bottom.tap()
        let island = app.descendants(matching: .any).matching(identifier: "details-island").firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(bottom.frame.maxY, island.frame.minY + 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "viewer-light-details"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDarkModeAndLargeTextDetailsRemainUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let region = app.buttons["region-r001"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        region.tap()
        XCTAssertTrue(app.buttons["close-details"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "viewer-dark-large-text"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["close-details"].tap()
        XCTAssertTrue(app.buttons["toggle-original"].isHittable)
    }

    func testScreenshotEdgesAreReachableOutsideNativeControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let top = app.buttons["region-r004"]
        XCTAssertTrue(top.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(top.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(app.buttons["region-r005"].frame.maxY, app.frame.maxY - 16,
                                 String(describing: app.scrollViews["screenshot-canvas"].value))
        top.tap()
        XCTAssertTrue(app.buttons["close-details"].waitForExistence(timeout: 5))
        let before = top.frame
        app.buttons["close-details"].tap()
        XCTAssertEqual(top.frame.minY, before.minY, accuracy: 2)
        XCTAssertTrue(top.isHittable)
    }

    func testBackReturnsHomeWithoutReopeningScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["region-r001"].waitForExistence(timeout: 20))
        goBack(app)
        let reopen = app.descendants(matching: .any).matching(identifier: "open-last-screenshot").firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        XCTAssertTrue(reopen.isHittable)
        reopen.tap()
        XCTAssertTrue(app.buttons["region-r001"].waitForExistence(timeout: 5))
        goBack(app)
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        XCTAssertTrue(reopen.isHittable)
    }

    func testFullResolutionScreenshotStartsFittedAndCanZoomBackOut() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--large-image", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let region = app.buttons["region-r001"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        let canvas = app.scrollViews["screenshot-canvas"]
        let fitted = region.frame.width
        XCTAssertLessThan(fitted, canvas.frame.width)
        XCTAssertGreaterThanOrEqual(app.buttons["region-r004"].frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(app.buttons["region-r005"].frame.maxY, app.frame.maxY - 16,
                                 String(describing: canvas.value))
        canvas.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(region.frame.width, fitted * 1.4)
        canvas.pinch(withScale: 0.2, velocity: -1)
        XCTAssertEqual(region.frame.width, fitted, accuracy: 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "viewer-full-resolution-fitted"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPriceConversionOfflineAndHistoryReopen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let price = app.buttons["region-r002"]
        XCTAssertTrue(price.waitForExistence(timeout: 20))
        price.tap()
        tapInIsland("Convert price", app)
        let pln = app.staticTexts["zł44.00"]
        XCTAssertTrue(pln.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Approx. · 2026-11-12"].exists)
        let island = app.scrollViews["details-island"]
        XCTAssertLessThanOrEqual(price.frame.maxY, island.frame.minY + 3)
        reveal(app.buttons["Hide conversion"], in: island)
        attach(app, "dated-offline-conversion")
        app.buttons["Hide conversion"].tap()
        XCTAssertTrue(app.buttons["Convert from CNY"].exists)
        goBack(app)
        let row = app.buttons["history-session"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        attach(app, "screenshot-history")
        row.tap()
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        tapInIsland("Convert from CNY", app)
        XCTAssertTrue(pln.waitForExistence(timeout: 5))
    }

    func testIndependentUnmarkedAmountsAndDraftCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let region = app.buttons["region-r008"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        region.tap()
        tapInIsland("Convert amount", app)
        XCTAssertFalse(app.buttons["Confirm & convert"].isEnabled)
        tapInIsland("PLN", app)
        tapInIsland("Confirm & convert", app)
        XCTAssertTrue(app.staticTexts["¥256.00"].waitForExistence(timeout: 5))
        tapInIsland("Change currency", app)
        tapInIsland("USD", app)
        tapInIsland("Cancel", app)
        XCTAssertTrue(app.staticTexts["¥256.00"].exists)
        tapInIsland("Amount 2, 128", app)
        tapInIsland("Convert amount", app)
        XCTAssertFalse(app.buttons["Confirm & convert"].isEnabled)
        tapInIsland("EUR", app)
        tapInIsland("Confirm & convert", app)
        XCTAssertTrue(app.staticTexts["¥1024.00"].waitForExistence(timeout: 5))
        tapInIsland("Change currency", app)
        tapInIsland("USD", app)
        tapInIsland("Save & update", app)
        XCTAssertTrue(app.staticTexts["$128.00"].waitForExistence(timeout: 5))
    }

    func testNoRatesRetryLeavesTranslationReadable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--no-rates"]
        app.launch()
        let region = app.buttons["region-r002"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        region.tap()
        tapInIsland("Convert price", app)
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        tapInIsland("Retry", app)
        XCTAssertTrue(app.staticTexts["Reference rates are unavailable. Retry when connected."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail-translation"].label, "¥88.00")
    }

    func testMissingOriginalCanBeDeletedFromHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--missing-original"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Screenshot unavailable"].waitForExistence(timeout: 20))
        attach(app, "missing-original")
        goBack(app)
        let row = app.buttons["history-session"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No recent screenshots"].waitForExistence(timeout: 5))
        attach(app, "empty-history")
    }

    func testHighFidelityReplacementLeavesFutureCaptureOnFast() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--warm-capture"]
        app.launch()
        let region = app.buttons["region-r001"]
        XCTAssertTrue(region.waitForExistence(timeout: 20))
        let original = region.frame
        app.buttons["More"].tap()
        app.buttons["Translate again"].tap()
        app.buttons["Apple High Fidelity"].tap()
        region.tap()
        XCTAssertEqual(app.staticTexts["detail-translation"].label, "Blue · premium")
        XCTAssertEqual(region.frame.width, original.width, accuracy: 1)
        app.buttons["More"].tap()
        app.buttons["Translate again"].tap()
        let requested = app.buttons["Apple High Fidelity (requested)"]
        XCTAssertTrue(requested.waitForExistence(timeout: 5))
        requested.tap()
        app.buttons["More"].tap()
        app.buttons["Submit second screenshot"].tap()
        let secondTranslation = expectation(for: NSPredicate(format: "label == %@", "红色, Red"), evaluatedWith: region)
        wait(for: [secondTranslation], timeout: 15)
        app.buttons["More"].tap()
        app.buttons["Translate again"].tap()
        let fast = app.buttons["Apple Fast (requested)"]
        XCTAssertTrue(fast.waitForExistence(timeout: 5))
        fast.tap()
        goBack(app)
        let rows = app.buttons.matching(identifier: "history-session")
        XCTAssertEqual(rows.count, 2)
        app.buttons["Delete group"].tap()
        let confirm = app.buttons["Delete screenshots"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No recent screenshots"].waitForExistence(timeout: 5))
    }

    private func tapInIsland(_ label: String, _ app: XCUIApplication) {
        let element = app.buttons[label]
        XCTAssertTrue(element.waitForExistence(timeout: 5), label)
        reveal(element, in: app.scrollViews["details-island"])
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in island: XCUIElement) {
        for _ in 0..<5 {
            let visible = island.frame.insetBy(dx: 0, dy: 5)
            if visible.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)), element.isHittable { return }
            if element.frame.midY < visible.midY { island.swipeDown() } else { island.swipeUp() }
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func goBack(_ app: XCUIApplication) {
        // The Duo exposes its native back control in a side rail, outside NavigationBar.
        let back = app.buttons["BackButton"]
        if back.exists { back.tap() }
        else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }
}
