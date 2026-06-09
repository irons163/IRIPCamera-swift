//
//  ScreenshotCaptureTests.swift
//  IRIPCamera-swiftUITests
//
//  Utility UI test that drives the app to the Settings page and captures
//  screenshots (as attachments) for the README. Run explicitly with:
//  -only-testing:IRIPCamera-swiftUITests/ScreenshotCaptureTests
//

import XCTest

final class ScreenshotCaptureTests: XCTestCase {

    @MainActor
    func testCaptureSettingsScreen() throws {
        let app = XCUIApplication()
        // Seed UserDefaults via the NSArgumentDomain so the Settings page shows
        // a populated, multi-URL configuration.
        app.launchArguments += [
            "-EnableRTSPURL", "YES",
            "-RTSPURL", "rtsp://stream.strba.sk:1935/strba/VYHLAD_JAZERO.stream",
            "-RTSPURL2", "rtsp://807e9439d5ca.entrypoint.cloud.wowza.com:1935/app-rC94792j/068b9c9a_stream2",
            "-RTSPURL3", "rtsp://77.110.228.219/axis-media/media.amp",
            "-DisplayMode", "4"
        ]
        app.launch()

        // Landing screen is a table; open the player entry.
        let entry = app.tables.cells.element(boundBy: 0)
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "Landing cell not found")
        entry.tap()

        // Player view with the Settings button.
        Thread.sleep(forTimeInterval: 1.5)
        attach(XCUIScreen.main.screenshot(), name: "player")

        // Navigate to Settings and capture the multi-URL configuration page.
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15), "Settings button not found")
        settingsButton.tap()

        // Let the table populate / animation settle.
        Thread.sleep(forTimeInterval: 1.5)
        attach(XCUIScreen.main.screenshot(), name: "settings")
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
