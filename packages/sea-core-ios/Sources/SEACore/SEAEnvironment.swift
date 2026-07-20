import Foundation

/// Compiled security configuration (contract §3.3, spec §7.1/§6.2).
///
/// `authDomains` is the build-compiled allowlist. Host-supplied
/// `allowedDomains` on `SEAConfig` can only narrow this set — it can never
/// widen it. This is enforced by `effectiveAllowlist(narrowedBy:)`, the single
/// place both the URL validator and the navigation policy compute the
/// effective set from.
public struct SEAEnvironment {
    public let authDomains: Set<String>
    public let callbackScheme: String

    public init(authDomains: Set<String>, callbackScheme: String) {
        self.authDomains = Set(authDomains.map(SEAEnvironment.normalizeHost))
        self.callbackScheme = callbackScheme
    }

    /// Lowercases (ASCII-lowercased) and strips a single trailing dot, per the
    /// host-matching rules in contract §5.
    public static func normalizeHost(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    /// Effective allowlist per contract §3.3: host input can narrow, never
    /// widen. Empty host input means "use the compiled set unchanged". A host
    /// list disjoint from the compiled set yields an empty effective allowlist
    /// (fail closed, not fail open).
    public func effectiveAllowlist(narrowedBy hostAllowlist: [String]) -> Set<String> {
        guard !hostAllowlist.isEmpty else { return authDomains }
        let narrowed = Set(hostAllowlist.map(SEAEnvironment.normalizeHost))
        return authDomains.intersection(narrowed)
    }

    /// Build-config-selected compiled environment.
    ///
    /// The concrete domains here are placeholders illustrating the compiled
    /// (not host-supplied) nature of this allowlist, matching the examples
    /// used throughout the spec/contract ("auth.bank.com",
    /// "bankerise-auth"). A production integration is expected to replace
    /// these with its real per-environment domains — see the package README.
    ///
    /// Recall the §7.1 rule: `SEAConfig.allowedDomains` can only *narrow* this
    /// compiled set, never widen it. A host not compiled in here can never be
    /// loaded, no matter what a caller passes. That is why the local dev
    /// domains below have to live in the compiled set for the demo/device-lab
    /// loop to reach a locally-hosted Keycloak — and why they are fenced
    /// behind `#if DEBUG` so a release build can never carry them.
    public static let current: SEAEnvironment = {
        #if SEA_ENV_PRODUCTION
        return SEAEnvironment(
            authDomains: ["auth.bank.com"],
            callbackScheme: "bankerise-auth"
        )
        #elseif SEA_ENV_STAGING
        return SEAEnvironment(
            authDomains: ["auth-staging.bank.com"],
            callbackScheme: "bankerise-auth"
        )
        #else
        var domains: Set<String> = ["auth.bank.com", "auth-staging.bank.com"]
        #if DEBUG
        // DEV ONLY, and structurally unable to escape a release build: the
        // local TLS Keycloak (infra/) and the demo harness authenticate
        // against these. `#if DEBUG` is compiled out of any release
        // configuration, so no release binary — flagged or unflagged — can
        // ever have "localhost" in its allowlist.
        domains.formUnion(["localhost", "auth.bank.local"])
        #endif
        return SEAEnvironment(authDomains: domains, callbackScheme: "bankerise-auth")
        #endif
    }()
}
