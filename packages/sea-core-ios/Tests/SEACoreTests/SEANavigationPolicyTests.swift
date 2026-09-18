import XCTest
@testable import SEACore

final class SEANavigationPolicyTests: XCTestCase {
    private let env = SEAEnvironment(
        authDomains: ["auth.bank.com", "idp.partner-example.com"],
        callbackScheme: "bankerise-auth"
    )

    private func decide(
        _ urlString: String,
        isMainFrame: Bool = true,
        currentPageHost: String? = nil,
        hostAllowlist: [String] = []
    ) -> SEANavigationDecision {
        let url = URL(string: urlString)!
        let request = SEANavigationRequest(url: url, isMainFrame: isMainFrame, currentPageHost: currentPageHost)
        return SEANavigationPolicy.decide(for: request, environment: env, hostAllowlist: hostAllowlist)
    }

    // MARK: - Rule 1: callback scheme preempts everything

    func test_callbackScheme_isCaptured() {
        let decision = decide("bankerise-auth://callback?code=abc123&state=xyz")
        guard case .capture(let params) = decision else {
            return XCTFail("expected .capture, got \(decision)")
        }
        XCTAssertEqual(params["code"], "abc123")
        XCTAssertEqual(params["state"], "xyz")
    }

    func test_callbackScheme_isCaseInsensitive() {
        let decision = decide("BANKERISE-AUTH://callback?code=abc123")
        guard case .capture = decision else {
            return XCTFail("expected .capture, got \(decision)")
        }
    }

    func test_callbackScheme_preemptsEvenOnSubresourceFrame() {
        let decision = decide("bankerise-auth://callback?code=abc", isMainFrame: false, currentPageHost: "auth.bank.com")
        guard case .capture = decision else {
            return XCTFail("expected .capture, got \(decision)")
        }
    }

    func test_callbackScheme_errorShapedCallback_isStillCaptureNotBlock() {
        // contract §6.3 / spec §6.3: error-shaped callbacks are delivered
        // through onCaptured, not onError.
        let decision = decide("bankerise-auth://callback?error=access_denied&error_description=User+cancelled")
        guard case .capture(let params) = decision else {
            return XCTFail("expected .capture, got \(decision)")
        }
        XCTAssertEqual(params["error"], "access_denied")
    }

    // MARK: - Rule 2: about:blank for the initial frame

    func test_aboutBlank_initialMainFrame_isAllowed() {
        let decision = decide("about:blank", isMainFrame: true, currentPageHost: nil)
        XCTAssertEqual(decision, .allow)
    }

    func test_aboutBlank_afterAPageHasCommitted_isBlocked() {
        // Not "initial" anymore — must fail closed, not get a blanket pass.
        let decision = decide("about:blank", isMainFrame: true, currentPageHost: "auth.bank.com")
        guard case .block = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
    }

    // MARK: - Rule 3: https + allowlisted host + main frame or same-origin subresource

    func test_httpsAllowlistedHost_mainFrame_isAllowed() {
        XCTAssertEqual(decide("https://auth.bank.com/login"), .allow)
    }

    func test_httpsAllowlistedHost_subresourceSameOrigin_isAllowed() {
        let decision = decide("https://auth.bank.com/style.css", isMainFrame: false, currentPageHost: "auth.bank.com")
        XCTAssertEqual(decision, .allow)
    }

    func test_httpsAllowlistedHost_subresourceCrossOriginBetweenTwoAllowlistedDomains_isBlocked() {
        let decision = decide(
            "https://idp.partner-example.com/script.js",
            isMainFrame: false,
            currentPageHost: "auth.bank.com"
        )
        guard case .block(let reason) = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
        XCTAssertEqual(reason, "subresource_cross_origin")
    }

    func test_mainFrameNavigationBetweenTwoAllowlistedDomains_isAllowed() {
        // Main-frame hops between allowlisted domains (e.g. broker IdPs) are
        // fine even though the current page host differs.
        let decision = decide(
            "https://idp.partner-example.com/authorize",
            isMainFrame: true,
            currentPageHost: "auth.bank.com"
        )
        XCTAssertEqual(decision, .allow)
    }

    func test_narrowedHostAllowlist_stillEnforced() {
        let decision = decide("https://idp.partner-example.com/authorize", hostAllowlist: ["auth.bank.com"])
        guard case .block = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
    }

    // MARK: - AllowedSchemes (contract §5/§6, mirrors SEAAuthorizeURLValidator)

    func test_httpBlockedByDefault_evenWithHostAllowlisted() {
        // `env` above uses the default allowedSchemes (unspecified -> {"https"}).
        let decision = decide("http://auth.bank.com/login")
        guard case .block(let reason) = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
        XCTAssertEqual(reason, "scheme_not_allowed")
    }

    func test_httpAllowed_whenEnvironmentExplicitlyAllowsIt() {
        // Regression test: the very first navigation (the initial
        // `webView.load(authorizeURL)`) goes through this same policy, so an
        // authorize URL that already passed `SEAAuthorizeURLValidator`
        // because the host app opted into "http" via SEASecurityConfig.plist
        // must not be silently blocked here on that same scheme.
        let devEnv = SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth",
            allowedSchemes: ["https", "http"]
        )
        let url = URL(string: "http://auth.bank.com/login")!
        let request = SEANavigationRequest(url: url, isMainFrame: true, currentPageHost: nil)
        let decision = SEANavigationPolicy.decide(for: request, environment: devEnv, hostAllowlist: [])
        XCTAssertEqual(decision, .allow)
    }

    func test_schemeOtherThanExplicitAllowlist_stillBlocked_whenHttpAllowed() {
        // Allowing "http" must not become "allow anything".
        let devEnv = SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth",
            allowedSchemes: ["https", "http"]
        )
        let url = URL(string: "javascript:alert(1)")!
        let request = SEANavigationRequest(url: url, isMainFrame: true, currentPageHost: nil)
        let decision = SEANavigationPolicy.decide(for: request, environment: devEnv, hostAllowlist: [])
        guard case .block(let reason) = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
        XCTAssertEqual(reason, "scheme_not_allowed")
    }

    // MARK: - Rule 4: blocked-scheme corpus

    private let blockedSchemeURLs: [String] = [
        "http://auth.bank.com/login",
        "file:///etc/passwd",
        "content://media/external/images",
        "intent://scan/#Intent;scheme=zxing;end",
        "javascript:alert(document.cookie)",
        "data:text/html;base64,PHNjcmlwdD4=",
        "tel:+123456789",
        "mailto:someone@example.com",
        "some-other-custom-scheme://payload"
    ]

    func test_blockedSchemeCorpus_allBlocked() {
        for urlString in blockedSchemeURLs {
            guard let url = URL(string: urlString) else {
                XCTFail("could not construct URL: \(urlString)")
                continue
            }
            let request = SEANavigationRequest(url: url, isMainFrame: true, currentPageHost: nil)
            let decision = SEANavigationPolicy.decide(for: request, environment: env, hostAllowlist: [])
            guard case .block = decision else {
                XCTFail("[\(urlString)] expected .block, got \(decision)")
                continue
            }
        }
    }

    func test_hostNotInAllowlist_isBlocked() {
        let decision = decide("https://evil.io/phish")
        guard case .block(let reason) = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
        XCTAssertEqual(reason, "host_not_allowlisted")
    }

    func test_lookalikeHostSuffix_isBlocked() {
        let decision = decide("https://auth.bank.com.evil.io/phish")
        guard case .block = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
    }

    // MARK: - Block reason never carries raw host/URL (telemetry-safety adjacent)

    func test_blockReason_isASymbolicStringNeverContainingTheHost() {
        let decision = decide("https://attacker-controlled.example.com/x")
        guard case .block(let reason) = decision else {
            return XCTFail("expected .block, got \(decision)")
        }
        XCTAssertFalse(reason.contains("attacker-controlled"))
        XCTAssertFalse(reason.contains("example.com"))
    }
}
