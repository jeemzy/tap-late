import XCTest

@MainActor final class ViewerTests: XCTestCase {
    func testSelectToggleAndRevealBottomRegion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
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
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let top = app.buttons["region-r004"]
        XCTAssertTrue(top.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(top.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(app.buttons["region-r005"].frame.maxY, app.frame.maxY - 16)
        top.tap()
        XCTAssertTrue(app.buttons["close-details"].waitForExistence(timeout: 5))
        let before = top.frame
        app.buttons["close-details"].tap()
        XCTAssertEqual(top.frame.minY, before.minY, accuracy: 2)
        XCTAssertTrue(top.isHittable)
    }
}
