import XCTest
@testable import SEACore

/// Spec §10.4 step 1 (live: ceremony JS error surfaced via Keycloak's error
/// redirect). `SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable` is a
/// pure predicate over already-extracted `SEACallbackParams` — see the
/// type's doc comment for why it is intentionally NOT wired into the live
/// navigation path yet (spike-provisional Keycloak error vocabulary).
final class SEAWebAuthnLiveFailureTests: XCTestCase {
    private struct Case {
        let name: String
        let error: String?
        let expected: Bool
    }

    private let cases: [Case] = [
        Case(name: "nil error is not a webauthn signal", error: nil, expected: false),
        Case(name: "empty error is not a webauthn signal", error: "", expected: false),
        Case(name: "generic access_denied is not a webauthn signal", error: "access_denied", expected: false),
        Case(name: "generic login_required is not a webauthn signal", error: "login_required", expected: false),
        Case(name: "webauthn_error matches", error: "webauthn_error", expected: true),
        Case(name: "not_allowed_error matches", error: "not_allowed_error", expected: true),
        Case(name: "not_supported_error matches", error: "not_supported_error", expected: true),
        Case(name: "security_error matches", error: "security_error", expected: true),
        Case(name: "webauthn_unsupported matches", error: "webauthn_unsupported", expected: true),
        Case(name: "matching is case-insensitive", error: "WEBAUTHN_ERROR", expected: true),
        Case(name: "unrelated substring containing webauthn does not loosely match", error: "webauthn_error_extra_suffix", expected: false)
    ]

    func test_indicatesWebauthnUnavailable_acrossTheSignalVocabulary() {
        for testCase in cases {
            let raw: [String: String] = testCase.error.map { ["error": $0] } ?? [:]
            let params = SEACallbackParams(raw: raw)
            XCTAssertEqual(
                SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params),
                testCase.expected,
                testCase.name
            )
        }
    }

    func test_indicatesWebauthnUnavailable_ignoresOtherParams() {
        let params = SEACallbackParams(raw: [
            "code": "abc",
            "state": "xyz",
            "error": "webauthn_error"
        ])
        XCTAssertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    func test_indicatesWebauthnUnavailable_successfulCallbackWithNoError_isFalse() {
        let params = SEACallbackParams(raw: ["code": "abc", "state": "xyz"])
        XCTAssertFalse(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }
}
