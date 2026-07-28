import Foundation

/// Host-app-supplied security configuration (contract §3.3, spec §7.1/§6.2).
///
/// `authDomains` is the allowlist loaded from the host application's own
/// bundled `SEASecurityConfig.plist` (see `.current`) — not compiled into
/// SEACore. Host-supplied `allowedDomains` on `SEAConfig` can only narrow
/// this set — it can never widen it. This is enforced by
/// `effectiveAllowlist(narrowedBy:)`, the single place both the URL
/// validator and the navigation policy compute the effective set from.
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

    /// Runtime-loaded security config, sourced from the HOST APPLICATION's
    /// own bundle — never compiled into SEACore.
    ///
    /// SEACore is a single shared binary embedded by many different bank
    /// apps, each with its own callback URL scheme and auth-domain
    /// allowlist. Those values cannot be baked into SEACore at the
    /// library's own build time (that would require a different SEACore
    /// compile per integrating app); they must instead be supplied by each
    /// host application at *application*-packaging time. This is the
    /// mechanism that does that: on first access, `.current` reads a
    /// dedicated `SEASecurityConfig.plist` out of `Bundle.main` — i.e. the
    /// bundle of whatever app has embedded SEACore, not SEACore's own SPM
    /// resource bundle — and resolves it once (`static let`).
    ///
    /// This keeps the callback scheme / domain allowlist native-trusted:
    /// they are read from a plist the host app bundles into its own signed
    /// app target, so they are just as untouchable from JS/React Native as
    /// the old compiled values were, while no longer requiring SEACore
    /// itself to be recompiled per bank. Each integrating app ships its own
    /// `SEASecurityConfig.plist`; a dev/staging/prod split, if a given app
    /// wants one, is achieved by swapping which plist file that app's build
    /// configuration includes — entirely outside SEACore's concern.
    ///
    /// Any problem loading or parsing the plist (missing file, unreadable,
    /// malformed dictionary, missing/wrong-typed `CallbackScheme`,
    /// missing/empty `AuthDomains`) fails closed to
    /// `SEAEnvironment(authDomains: [], callbackScheme: "")`: an empty
    /// `authDomains` set means `effectiveAllowlist` can never contain
    /// anything (every host check fails), and an empty-string
    /// `callbackScheme` can never equal a real URL's `.scheme` (never `""`
    /// for a URL that parses at all), so navigation capture can never
    /// trigger either. This mirrors the "any ambiguity resolves to failure"
    /// principle used throughout the validator/policy — never fail open,
    /// and never crash the host app's release build over a config mistake
    /// (the failure path only raises `assertionFailure`, a DEBUG-only
    /// no-op in Release, to loudly flag the misconfiguration to the
    /// integrating developer).
    public static let current: SEAEnvironment = load(from: .main)

    /// Plist schema for `SEASecurityConfig.plist`, matched against the flat
    /// two-key dictionary the host app bundles:
    /// ```xml
    /// <key>CallbackScheme</key>
    /// <string>bkrmob</string>
    /// <key>AuthDomains</key>
    /// <array>
    ///     <string>keycloak.example.com</string>
    /// </array>
    /// ```
    private struct SecurityConfigPlist: Decodable {
        let CallbackScheme: String
        let AuthDomains: [String]
    }

    /// Test seam only: the failure path below reports through this instead
    /// of calling `assertionFailure` inline, purely so
    /// `SEAEnvironmentLoadingTests` can substitute a no-op while asserting
    /// on the fail-closed *return value* of `load(from:)`. `assertionFailure`
    /// traps the process in Debug builds by design (see `.current`'s doc
    /// comment) — exactly what we want for a real integrating app that
    /// shipped a broken plist, but it would just as surely crash the very
    /// test that verifies the fail-closed behavior. No production or
    /// integrating-app code ever touches this: it defaults to calling
    /// straight through to `assertionFailure`, so real behavior — loud
    /// DEBUG-time trap, silent no-op in Release — is exactly as documented
    /// above and unchanged by this seam existing.
    static var reportLoadFailure: (String) -> Void = { assertionFailure($0) }

    /// Loads `SEASecurityConfig.plist` from `bundle` and fails closed (see
    /// `.current`'s doc comment) on any problem. `internal`, not `private`,
    /// so unit tests in this module can exercise it directly against a
    /// test-fixture bundle without needing to fake `Bundle.main`.
    static func load(from bundle: Bundle) -> SEAEnvironment {
        let failClosed = SEAEnvironment(authDomains: [], callbackScheme: "")

        guard let url = bundle.url(forResource: "SEASecurityConfig", withExtension: "plist") else {
            reportLoadFailure(
                "SEACore: SEASecurityConfig.plist not found in \(bundle.bundleURL.lastPathComponent). " +
                "The host app must bundle a SEASecurityConfig.plist (CallbackScheme + AuthDomains) " +
                "in its own app target. Failing closed: no auth domains or callback scheme are trusted."
            )
            return failClosed
        }

        guard let data = try? Data(contentsOf: url) else {
            reportLoadFailure(
                "SEACore: SEASecurityConfig.plist at \(url.path) could not be read. Failing closed."
            )
            return failClosed
        }

        let decoded: SecurityConfigPlist
        do {
            decoded = try PropertyListDecoder().decode(SecurityConfigPlist.self, from: data)
        } catch {
            reportLoadFailure(
                "SEACore: SEASecurityConfig.plist at \(url.path) is malformed or missing required keys " +
                "(CallbackScheme: String, AuthDomains: [String]): \(error). Failing closed."
            )
            return failClosed
        }

        guard !decoded.CallbackScheme.isEmpty, !decoded.AuthDomains.isEmpty else {
            reportLoadFailure(
                "SEACore: SEASecurityConfig.plist at \(url.path) has an empty CallbackScheme or " +
                "AuthDomains. Failing closed."
            )
            return failClosed
        }

        return SEAEnvironment(authDomains: Set(decoded.AuthDomains), callbackScheme: decoded.CallbackScheme)
    }
}
