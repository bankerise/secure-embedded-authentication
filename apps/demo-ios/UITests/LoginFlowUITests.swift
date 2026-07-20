import XCTest

/// End-to-end smoke test for the SEA login surface (§23.3 device-lab harness).
///
/// This drives the real UI: it taps "Start login", waits for the SEA WebView
/// sheet to present, and confirms the Keycloak login form actually rendered
/// inside the embedded WebView — i.e. the §6 handoff perimeter works against
/// the local TLS Keycloak, with SEACore's validator and navigation policy in
/// their production configuration.
///
/// Preconditions (see infra/README.md):
///   - `docker compose up -d` + `./provision-realm.sh`
///   - `./trust-ca-simulator.sh` with this simulator booted
/// Without them the WebView load fails and this test fails loudly — which is
/// the correct signal, not a reason to weaken anything.
final class LoginFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Poll `condition` until it holds or `timeout` elapses.
    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            wait(0.5)
        }
        return condition()
    }

    /// Focus a WKWebView field and type into it. Tapping the element's center
    /// coordinate (rather than the element) is the reliable way to land
    /// keyboard focus inside a WKWebView under XCUITest. Retap until the
    /// software keyboard actually appears — the WKWebView secure field will
    /// not accept synthesized focus while the previous field's keyboard is
    /// still animating out.
    private func typeInto(_ app: XCUIApplication, _ element: XCUIElement, _ text: String) {
        for _ in 0..<5 {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.keyboards.element.waitForExistence(timeout: 2) { break }
            wait(0.3)
        }
        element.typeText(text)
    }

    func test_startLogin_presentsKeycloakFormInEmbeddedWebView() throws {
        let app = XCUIApplication()
        app.launch()

        let startButton = app.buttons["Start login"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Config screen should show the Start login button")
        startButton.tap()

        // The SEA surface is a WKWebView presented in a sheet. Wait for the
        // web view to exist, then for the Keycloak form's username field to
        // become hittable — proof the page loaded over TLS and rendered, not
        // just that a blank sheet appeared.
        let webView = app.webViews.firstMatch
        let sheetPresented = webView.waitForExistence(timeout: 20)
        if !sheetPresented {
            // Leave a full diagnostic trail: the element tree tells us whether
            // a sheet presented at all, and whether the app surfaced a start
            // error instead of presenting.
            print("SEA-DIAG element tree:\n\(app.debugDescription)")
        }
        XCTAssertTrue(sheetPresented,
                      "SEA WebView sheet should present after Start login")

        let usernameField = webView.textFields.firstMatch
        let appeared = usernameField.waitForExistence(timeout: 20)

        // Attach a screenshot regardless, so a device-lab run always leaves
        // visual evidence of what the embedded surface actually showed.
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "sea-embedded-keycloak"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(appeared,
                      "Keycloak username field should render inside the embedded WebView")
    }

    /// The whole point of the design (§6.3): drive a real login to completion
    /// and prove SEA intercepts the custom-scheme callback IN-PROCESS and
    /// delivers a `code` via onCaptured, dismissing the sheet.
    ///
    /// Credentials here are the fabricated local test account provisioned by
    /// infra/provision-realm.sh (demo / demo123) against a throwaway localhost
    /// realm — not anyone's real credentials.
    func test_completeLogin_capturesAuthorizationCode() throws {
        let app = XCUIApplication()
        app.launch()

        let startButton = app.buttons["Start login"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20), "WebView should present")

        let username = webView.textFields.firstMatch
        XCTAssertTrue(username.waitForExistence(timeout: 20), "Username field should render")
        typeInto(app, username, "demo")

        // XCUITest cannot reliably land synthesized keyboard focus on a
        // WKWebView *secure* text field. Rather than fight that, this test is
        // human-in-the-loop: it fills the username and reveals the password
        // field, then hands off. A tester types the password (demo123) and
        // taps Sign In in the simulator. Nothing about SEA or the §6.3 capture
        // path is stubbed — the tester is only standing in for the keyboard
        // synthesis XCUITest can't do here.
        let showPassword = webView.buttons["Show password"]
        if showPassword.waitForExistence(timeout: 5) { showPassword.tap() }

        // SEA dismisses the sheet the instant it captures the callback (§6.3),
        // so the WebView ceasing to exist is the capture signal. Wait for it
        // while the tester completes login manually.
        let sheetDismissed = waitFor(timeout: 150) { !webView.exists }
        XCTAssertTrue(sheetDismissed,
                      "Login sheet should dismiss once SEA captures the callback — "
                      + "type demo123 and tap Sign In in the simulator within the window")

        let resultTab = app.buttons["Result"]
        XCTAssertTrue(resultTab.waitForExistence(timeout: 10))
        resultTab.tap()

        let codeRow = app.staticTexts["code"]
        let captured = codeRow.waitForExistence(timeout: 15)

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "sea-captured-code"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(captured,
                      "onCaptured should deliver a 'code' param after successful login (§6.3)")
    }
}
