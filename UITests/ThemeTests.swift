import XCTest
final class ThemeTests: XCTestCase {
    func testBundledTunnelReachesHostWithoutSeparateVpn() {
        executionTimeAllowance = 360
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        let connected = app.staticTexts["Private tunnel • AI on 4090 host"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(300)
        while !connected.exists && Date() < deadline {
            let allow = springboard.alerts.buttons["Allow"]
            if allow.exists { allow.tap() }
            if connected.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(connected.exists, "The bundled iPhone Tor transport did not reach the pinned host from the remote simulator.")
    }
    func testThemeSelectionPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--theme-picker-preview"]
        app.launch()
        let matrix = app.buttons["theme-matrix"]
        XCTAssertTrue(matrix.waitForExistence(timeout: 10))
        matrix.tap()
        XCTAssertTrue(matrix.label.contains("selected"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["theme-matrix"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["theme-matrix"].label.contains("selected"))
        app.buttons["theme-ocean"].tap()
        XCTAssertTrue(app.buttons["theme-ocean"].label.contains("selected"))
        app.buttons["theme-classic"].tap()
        XCTAssertTrue(app.buttons["theme-classic"].label.contains("selected"))
    }
}
