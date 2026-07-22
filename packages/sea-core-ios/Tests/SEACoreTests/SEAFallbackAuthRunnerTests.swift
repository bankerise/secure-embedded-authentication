import XCTest
import UIKit
import AuthenticationServices
@testable import SEACore

/// Spec §10.4 fallback path. `SEAFallbackAuthRunner.mapResult` is the pure
/// `(url, error) -> outcome` mapping factored out of the
/// `ASWebAuthenticationSession` completion handler specifically so it can be
/// exercised here without driving `ASWebAuthenticationSession` itself
/// (which cannot be run headlessly in a unit test). The empty-callbackScheme
/// guard in `start()` is covered separately below, driving the whole runner
/// end-to-end (that path never touches `ASWebAuthenticationSession` at all,
/// so it's safe to run in-process).
final class SEAFallbackAuthRunnerTests: XCTestCase {
    // MARK: - mapResult: success

    func test_mapResult_withCallbackURL_extractsParamsVerbatim() {
        let url = URL(string: "bkrmob://callback?code=abc123&state=xyz")!
        let result = SEAFallbackAuthRunner.mapResult(url: url, error: nil)
        XCTAssertEqual(result, .captured(["code": "abc123", "state": "xyz"]))
    }

    func test_mapResult_withErrorShapedCallbackURL_stillCaptures() {
        // Error-shaped callbacks are delivered through onCaptured, never
        // onError (contract §3.4/§6.3) — same rule as the embedded path.
        let url = URL(string: "bkrmob://callback?error=access_denied&error_description=User%20cancelled")!
        let result = SEAFallbackAuthRunner.mapResult(url: url, error: nil)
        XCTAssertEqual(result, .captured(["error": "access_denied", "error_description": "User cancelled"]))
    }

    func test_mapResult_withNoQueryString_capturesEmptyParams() {
        let url = URL(string: "bkrmob://callback")!
        let result = SEAFallbackAuthRunner.mapResult(url: url, error: nil)
        XCTAssertEqual(result, .captured([:]))
    }

    // MARK: - mapResult: cancellation

    func test_mapResult_withCanceledLoginError_mapsToCancelled() {
        let error = NSError(
            domain: ASWebAuthenticationSessionErrorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        )
        let result = SEAFallbackAuthRunner.mapResult(url: nil, error: error)
        XCTAssertEqual(result, .cancelled)
    }

    // MARK: - mapResult: other errors

    func test_mapResult_withOtherASWebAuthError_mapsToNetworkError() {
        // A different ASWebAuthenticationSessionError.Code, e.g.
        // presentationContextNotProvided, is a real failure — not a user
        // cancellation — and must not be misclassified as .cancelled.
        let error = NSError(
            domain: ASWebAuthenticationSessionErrorDomain,
            code: ASWebAuthenticationSessionError.Code.presentationContextNotProvided.rawValue
        )
        let result = SEAFallbackAuthRunner.mapResult(url: nil, error: error)
        guard case .error(.network) = result else {
            return XCTFail("expected .error(.network), got \(result)")
        }
    }

    func test_mapResult_withUnrelatedError_mapsToNetworkError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let result = SEAFallbackAuthRunner.mapResult(url: nil, error: error)
        guard case .error(.network) = result else {
            return XCTFail("expected .error(.network), got \(result)")
        }
    }

    func test_mapResult_withNoURLAndNoError_mapsToNetworkErrorRatherThanCrashing() {
        // Defensive: ASWebAuthenticationSession's contract guarantees one of
        // url/error is non-nil, but the mapping must still fail closed
        // (never crash, never silently succeed) if that's ever violated.
        let result = SEAFallbackAuthRunner.mapResult(url: nil, error: nil)
        guard case .error(.network) = result else {
            return XCTFail("expected .error(.network), got \(result)")
        }
    }

    // MARK: - start(): empty callbackScheme guards fail closed to .webauthnUnavailable

    func test_start_withEmptyCallbackScheme_firesOnErrorWebauthnUnavailable_neverStartsASession() {
        let config = SEAConfig(authorizeURL: URL(string: "https://auth.bank.com/auth")!)
        // Empty callbackScheme is exactly SEAEnvironment's fail-closed value
        // (contract §3.3) for a missing/malformed SEASecurityConfig.plist.
        let environment = SEAEnvironment(authDomains: ["auth.bank.com"], callbackScheme: "")

        var capturedCount = 0
        var cancelledCount = 0
        var errors: [SEAError] = []
        let callbacks = SEASession.Callbacks(
            onCaptured: { _ in capturedCount += 1 },
            onCancelled: { cancelledCount += 1 },
            onError: { errors.append($0) }
        )

        let host = UIViewController()
        let runner = SEAFallbackAuthRunner(config: config, environment: environment, callbacks: callbacks, presentingViewController: host)
        runner.start()

        XCTAssertEqual(capturedCount, 0)
        XCTAssertEqual(cancelledCount, 0)
        XCTAssertEqual(errors, [.webauthnUnavailable])
    }

    func test_start_withEmptyCallbackScheme_isTerminalOnlyOnce() {
        let config = SEAConfig(authorizeURL: URL(string: "https://auth.bank.com/auth")!)
        let environment = SEAEnvironment(authDomains: ["auth.bank.com"], callbackScheme: "")

        var errorCount = 0
        let callbacks = SEASession.Callbacks(
            onCaptured: { _ in },
            onCancelled: {},
            onError: { _ in errorCount += 1 }
        )

        let host = UIViewController()
        let runner = SEAFallbackAuthRunner(config: config, environment: environment, callbacks: callbacks, presentingViewController: host)
        runner.start()
        runner.start()

        XCTAssertEqual(errorCount, 1)
    }
}
