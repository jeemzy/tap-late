import XCTest

@MainActor final class ViewerTests: XCTestCase {
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
        XCTAssertLessThanOrEqual(app.buttons["region-r005"].frame.maxY, app.frame.maxY - 16)
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
        canvas.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(region.frame.width, fitted * 1.4)
        canvas.pinch(withScale: 0.2, velocity: -1)
        XCTAssertEqual(region.frame.width, fitted, accuracy: 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "viewer-full-resolution-fitted"
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
