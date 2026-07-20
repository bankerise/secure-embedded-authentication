import XCTest
@testable import SEACore

/// Contract §3.3 / §10: host-supplied `allowedDomains` can only narrow the
/// compiled allowlist, never widen it; a disjoint host list fails closed to
/// an empty effective allowlist.
final class SEAEnvironmentAllowlistTests: XCTestCase {
    private let env = SEAEnvironment(
        authDomains: ["auth.bank.com", "idp.partner-example.com"],
        callbackScheme: "bankerise-auth"
    )

    func test_emptyHostAllowlist_usesCompiledSetUnchanged() {
        let effective = env.effectiveAllowlist(narrowedBy: [])
        XCTAssertEqual(effective, ["auth.bank.com", "idp.partner-example.com"])
    }

    func test_narrowingToSubsetWorks() {
        let effective = env.effectiveAllowlist(narrowedBy: ["auth.bank.com"])
        XCTAssertEqual(effective, ["auth.bank.com"])
    }

    func test_wideningIsImpossible() {
        // Host input tries to add a domain that isn't compiled in.
        let effective = env.effectiveAllowlist(narrowedBy: ["auth.bank.com", "not-compiled.example.com"])
        XCTAssertEqual(effective, ["auth.bank.com"])
        XCTAssertFalse(effective.contains("not-compiled.example.com"))
    }

    func test_fullyDisjointInput_failsClosedToEmptySet() {
        let effective = env.effectiveAllowlist(narrowedBy: ["totally-unrelated.example.com"])
        XCTAssertTrue(effective.isEmpty)
    }

    func test_hostAllowlistIsNormalizedBeforeIntersecting() {
        let effective = env.effectiveAllowlist(narrowedBy: ["AUTH.BANK.COM.", " "])
        XCTAssertEqual(effective, ["auth.bank.com"])
    }

    func test_compiledDomainsAreNormalizedAtInit() {
        let mixedCaseEnv = SEAEnvironment(authDomains: ["Auth.Bank.Com."], callbackScheme: "x")
        XCTAssertEqual(mixedCaseEnv.authDomains, ["auth.bank.com"])
    }
}
