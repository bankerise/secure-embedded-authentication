import XCTest
import WebKit
@testable import SEACore

/// Exercises `SEAAuthViewController`'s glue logic directly (it is internal,
/// visible here via `@testable import`) without loading its view — so none
/// of `viewDidLoad`'s WKWebView/timer/notification side effects run. This
/// keeps the terminal-callback and telemetry-redaction assertions
/// deterministic and independent of the WebKit runtime.
final class SEAAuthViewControllerTests: XCTestCase {
    private final class MockSink: SEATelemetrySink {
        var events: [SEAEvent] = []
        func record(_ event: SEAEvent) { events.append(event) }
    }

    private func makeConfig() -> SEAConfig {
        SEAConfig(authorizeURL: URL(string: "https://auth.bank.com/auth")!)
    }

    private func makeEnvironment() -> SEAEnvironment {
        SEAEnvironment(authDomains: ["auth.bank.com"], callbackScheme: "bankerise-auth")
    }

    override func tearDown() {
        SEASession.telemetrySink = nil
        super.tearDown()
    }

    func test_handleCapture_firesOnCapturedExactlyOnceEvenIfCalledRepeatedly() {
        var capturedCount = 0
        var cancelledCount = 0
        var errorCount = 0
        var lastParams: SEACallbackParams?

        let callbacks = SEASession.Callbacks(
            onCaptured: { params in capturedCount += 1; lastParams = params },
            onCancelled: { cancelledCount += 1 },
            onError: { _ in errorCount += 1 }
        )

        let vc = SEAAuthViewController(config: makeConfig(), environment: makeEnvironment(), callbacks: callbacks)

        // Simulate decidePolicyFor, the didCommit backstop, and the KVO
        // backstop all observing the same callback URL — the exact scenario
        // the POST-redirect backstop (contract §6) is designed for.
        vc.handleCapture(["code": "first"])
        vc.handleCapture(["code": "second"])
        vc.checkCallbackBackstop(url: URL(string: "bankerise-auth://callback?code=third"))

        XCTAssertEqual(capturedCount, 1)
        XCTAssertEqual(cancelledCount, 0)
        XCTAssertEqual(errorCount, 0)
        XCTAssertEqual(lastParams?.code, "first")
    }

    func test_applyBlockDecision_emitsNavBlockedWithHostHashNeverRawHost() {
        let sink = MockSink()
        SEASession.telemetrySink = sink

        let callbacks = SEASession.Callbacks(onCaptured: { _ in }, onCancelled: {}, onError: { _ in })
        let vc = SEAAuthViewController(config: makeConfig(), environment: makeEnvironment(), callbacks: callbacks)

        let blockedURL = URL(string: "https://evil.example.com/phish?token=leak-me")!
        vc.apply(decision: .block(reason: "host_not_allowlisted"), url: blockedURL) { _ in }

        guard let event = sink.events.first(where: { $0.name == SEATelemetryEventName.navBlocked }) else {
            return XCTFail("expected AUTH_NAV_BLOCKED event")
        }
        XCTAssertEqual(event.properties["scheme"], "https")
        XCTAssertNotNil(event.properties["host_hash"])
        XCTAssertNil(event.properties["reason"], "AUTH_NAV_BLOCKED must only carry {scheme, host_hash} per contract §20.1")

        for value in event.properties.values {
            XCTAssertFalse(value.contains("evil.example.com"))
            XCTAssertFalse(value.contains("leak-me"))
            XCTAssertFalse(value.contains(blockedURL.absoluteString))
        }
    }

    func test_applyCaptureDecision_firesOnCapturedAndEmitsCompletedEvent() {
        let sink = MockSink()
        SEASession.telemetrySink = sink

        var capturedParams: SEACallbackParams?
        let callbacks = SEASession.Callbacks(
            onCaptured: { capturedParams = $0 },
            onCancelled: {},
            onError: { _ in }
        )
        let vc = SEAAuthViewController(config: makeConfig(), environment: makeEnvironment(), callbacks: callbacks)

        vc.apply(decision: .capture(["code": "abc", "state": "xyz"]), url: URL(string: "bankerise-auth://callback")!) { _ in }

        XCTAssertEqual(capturedParams?.code, "abc")
        XCTAssertTrue(sink.events.contains { $0.name == SEATelemetryEventName.completed })
    }

    func test_applyAllowDecision_doesNotInvokeAnyTerminalCallback() {
        var capturedCount = 0
        var cancelledCount = 0
        var errorCount = 0
        let callbacks = SEASession.Callbacks(
            onCaptured: { _ in capturedCount += 1 },
            onCancelled: { cancelledCount += 1 },
            onError: { _ in errorCount += 1 }
        )
        let vc = SEAAuthViewController(config: makeConfig(), environment: makeEnvironment(), callbacks: callbacks)

        var handlerPolicy: WKNavigationActionPolicy?
        vc.apply(decision: .allow, url: URL(string: "https://auth.bank.com/next")!) { policy in
            handlerPolicy = policy
        }

        XCTAssertEqual(handlerPolicy, .allow)
        XCTAssertEqual(capturedCount, 0)
        XCTAssertEqual(cancelledCount, 0)
        XCTAssertEqual(errorCount, 0)
    }
}
