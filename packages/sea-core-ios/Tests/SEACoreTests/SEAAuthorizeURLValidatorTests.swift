import XCTest
@testable import SEACore

final class SEAAuthorizeURLValidatorTests: XCTestCase {
    private let env = SEAEnvironment(
        authDomains: ["auth.bank.com", "idp.partner-example.com"],
        callbackScheme: "bankerise-auth"
    )

    private func validate(_ urlString: String, narrowedBy hostAllowlist: [String] = []) -> Result<URL, SEAInvalidURLReason> {
        guard let url = URL(string: urlString) else {
            return .failure(.malformed)
        }
        return SEAAuthorizeURLValidator.validate(url, against: env, narrowedBy: hostAllowlist)
    }

    // MARK: - Happy path

    func test_validHTTPSAllowlistedHost_succeeds() {
        let result = validate("https://auth.bank.com/realms/mobile/protocol/openid-connect/auth")
        switch result {
        case .success(let url):
            XCTAssertEqual(url.host, "auth.bank.com")
        case .failure(let reason):
            XCTFail("expected success, got \(reason)")
        }
    }

    func test_validHTTPSWithExplicitPort443_succeeds() {
        assertSucceeds("https://auth.bank.com:443/auth")
    }

    // MARK: - Table-driven: every SEAInvalidURLReason path

    private struct Case {
        let name: String
        let url: String
        let expected: SEAInvalidURLReason
        let hostAllowlist: [String]
        init(_ name: String, _ url: String, _ expected: SEAInvalidURLReason, hostAllowlist: [String] = []) {
            self.name = name
            self.url = url
            self.expected = expected
            self.hostAllowlist = hostAllowlist
        }
    }

    private let reasonCases: [Case] = [
        Case("http scheme", "http://auth.bank.com/auth", .scheme),
        Case("uppercase HTTP scheme", "HTTP://auth.bank.com/auth", .scheme),
        Case("custom scheme", "bankerise-auth://auth.bank.com/auth", .scheme),
        Case("javascript scheme", "javascript:alert(1)", .scheme),
        Case("userinfo present", "https://user:pass@auth.bank.com/auth", .userinfo),
        Case("userinfo user only", "https://sneaky@auth.bank.com/auth", .userinfo),
        Case("userinfo lookalike host", "https://auth.bank.com@evil.io/auth", .userinfo),
        Case("non-443 port", "https://auth.bank.com:8443/auth", .port),
        Case("port 80", "https://auth.bank.com:80/auth", .port),
        Case("host not in allowlist", "https://not-allowed.com/auth", .host),
        Case("suffix lookalike host (prefix)", "https://evil-auth.bank.com/auth", .host),
        Case("suffix lookalike host (appended)", "https://auth.bank.com.evil.io/auth", .host),
        Case("subdomain not explicitly allowlisted", "https://sub.auth.bank.com/auth", .host),
        Case("disjoint narrowed allowlist fails closed", "https://auth.bank.com/auth", .host, hostAllowlist: ["other.example.com"])
    ]

    func test_everyInvalidReason() {
        for testCase in reasonCases {
            let result = validate(testCase.url, narrowedBy: testCase.hostAllowlist)
            switch result {
            case .success:
                XCTFail("[\(testCase.name)] expected failure(\(testCase.expected)), got success")
            case .failure(let reason):
                XCTAssertEqual(reason, testCase.expected, "[\(testCase.name)]")
            }
        }
    }

    func test_lengthExceeds2048_fails() {
        let longPath = String(repeating: "a", count: 2100)
        let result = validate("https://auth.bank.com/\(longPath)")
        XCTAssertEqual(result.failureReason, .length)
    }

    func test_lengthExactly2048_succeeds() {
        // Build a URL whose absoluteString.utf8.count is exactly 2048.
        let prefix = "https://auth.bank.com/"
        let padding = String(repeating: "a", count: 2048 - prefix.utf8.count)
        let urlString = prefix + padding
        XCTAssertEqual(urlString.utf8.count, 2048)
        assertSucceeds(urlString)
    }

    func test_length2049_fails() {
        let prefix = "https://auth.bank.com/"
        let padding = String(repeating: "a", count: 2049 - prefix.utf8.count)
        let urlString = prefix + padding
        XCTAssertEqual(urlString.utf8.count, 2049)
        XCTAssertEqual(validate(urlString).failureReason, .length)
    }

    // MARK: - Host matching corpus (contract §5, §10)

    func test_hostMatchingIsCaseInsensitive() {
        assertSucceeds("https://AUTH.BANK.COM/auth")
        assertSucceeds("https://Auth.Bank.Com/auth")
    }

    func test_hostMatchingStripsSingleTrailingDot() {
        assertSucceeds("https://auth.bank.com./auth")
    }

    func test_evilAuthPrefixLookalike_isRejected() {
        XCTAssertEqual(validate("https://evil-auth.bank.com/auth").failureReason, .host)
    }

    func test_evilSuffixLookalike_isRejected() {
        XCTAssertEqual(validate("https://auth.bank.com.evil.io/auth").failureReason, .host)
    }

    func test_uppercaseHostStillMatchesAllowlist() {
        assertSucceeds("https://AUTH.BANK.COM/auth")
    }

    func test_userinfoLookalike_isRejectedAsUserinfoNotHost() {
        // https://auth.bank.com@evil.io/ — "auth.bank.com" is userinfo, the
        // real host is "evil.io". Must fail on the userinfo rule (evaluated
        // before the host rule), not merely because evil.io isn't allowlisted.
        XCTAssertEqual(validate("https://auth.bank.com@evil.io/").failureReason, .userinfo)
    }

    func test_punycodeHost_comparesOnPunycodeForm() {
        let punycodeEnv = SEAEnvironment(authDomains: ["xn--auth-imb.bank.com"], callbackScheme: "bankerise-auth")
        let url = URL(string: "https://xn--auth-imb.bank.com/auth")!
        let result = SEAAuthorizeURLValidator.validate(url, against: punycodeEnv, narrowedBy: [])
        switch result {
        case .success: break
        case .failure(let reason): XCTFail("expected success, got \(reason)")
        }
    }

    func test_punycodeHost_unicodeFormDoesNotMatchCompiledPunycode() {
        // The compiled allowlist holds the punycode form; a URL supplying the
        // decoded unicode host must not be treated as equivalent (no IDNA
        // decoding is performed anywhere in the validator).
        let punycodeEnv = SEAEnvironment(authDomains: ["xn--auth-imb.bank.com"], callbackScheme: "bankerise-auth")
        guard let url = URL(string: "https://au\u{00FE}h.bank.com/auth") else { return }
        let result = SEAAuthorizeURLValidator.validate(url, against: punycodeEnv, narrowedBy: [])
        XCTAssertEqual(result.failureReason, .host)
    }

    func test_malformedURL_failsClosed() {
        // A URL with an unparsable/invalid host token.
        if let url = URL(string: "https://") {
            let result = SEAAuthorizeURLValidator.validate(url, against: env, narrowedBy: [])
            XCTAssertEqual(result.failureReason, .host)
        }
    }

    // MARK: - AllowedSchemes (contract §5, spec §6.2)

    func test_httpRejectedByDefault_evenWithHostAllowlisted() {
        // `env` above uses the default allowedSchemes (unspecified -> {"https"}).
        XCTAssertEqual(validate("http://auth.bank.com/auth").failureReason, .scheme)
    }

    func test_httpAccepted_whenEnvironmentExplicitlyAllowsIt() {
        let devEnv = SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth",
            allowedSchemes: ["https", "http"]
        )
        let url = URL(string: "http://auth.bank.com/auth")!
        let result = SEAAuthorizeURLValidator.validate(url, against: devEnv, narrowedBy: [])
        switch result {
        case .success: break
        case .failure(let reason): XCTFail("expected success, got \(reason)")
        }
    }

    func test_httpsStillAccepted_whenEnvironmentAllowsBothSchemes() {
        let devEnv = SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth",
            allowedSchemes: ["https", "http"]
        )
        let url = URL(string: "https://auth.bank.com/auth")!
        let result = SEAAuthorizeURLValidator.validate(url, against: devEnv, narrowedBy: [])
        switch result {
        case .success: break
        case .failure(let reason): XCTFail("expected success, got \(reason)")
        }
    }

    func test_schemeOtherThanExplicitAllowlist_stillRejected() {
        // Allowing "http" must not become "allow anything" — javascript: etc.
        // are still rejected even when the environment has widened past the
        // https-only default.
        let devEnv = SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth",
            allowedSchemes: ["https", "http"]
        )
        let url = URL(string: "javascript:alert(1)")!
        let result = SEAAuthorizeURLValidator.validate(url, against: devEnv, narrowedBy: [])
        XCTAssertEqual(result.failureReason, .scheme)
    }

    func test_emptyAllowedSchemes_fallsBackToHttpsDefault() {
        // SEAEnvironment.init treats an empty allowedSchemes set as "unset",
        // not "allow nothing" — mirrors the same fail-safe-to-default
        // behavior as sea-core-android's SEAPropertiesLoader.
        let envWithEmptySchemes = SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth",
            allowedSchemes: []
        )
        XCTAssertEqual(envWithEmptySchemes.allowedSchemes, ["https"])
    }

    // MARK: - Helpers

    private func assertSucceeds(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) {
        switch validate(urlString) {
        case .success:
            break
        case .failure(let reason):
            XCTFail("expected success for \(urlString), got \(reason)", file: file, line: line)
        }
    }
}

private extension Result where Success == URL, Failure == SEAInvalidURLReason {
    var failureReason: SEAInvalidURLReason? {
        switch self {
        case .success: return nil
        case .failure(let reason): return reason
        }
    }
}
