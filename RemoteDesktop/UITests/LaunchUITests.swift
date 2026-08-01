import XCTest

/// Basic UI smoke test: the app launches and shows the login screen.
final class LaunchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAppLaunchesToLogin() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // The sign-in button exists on the auth screen.
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 8))
    }
}
