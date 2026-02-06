import XCTest

final class SapphoUITests: XCTestCase {
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Basic launch test
        XCTAssertTrue(app.exists)
    }
}
