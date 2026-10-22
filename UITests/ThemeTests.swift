import XCTest
final class ThemeTests: XCTestCase {
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
