import Foundation
import SEACore

/// Persisted tester-facing configuration for the demo harness (UserDefaults-backed).
///
/// This is harness state only — it has no bearing on SEACore's own security
/// posture. `allowedDomains` here is the *host-supplied narrowing list* that
/// SEACore intersects with `SEAEnvironment.current.authDomains` (loaded from
/// this app's own bundled `SEASecurityConfig.plist` — api-contract-ios-v1.md
/// §3.3) — it can never widen what the core accepts.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let gatewayBaseURL = "sea.demo.gatewayBaseURL"
        static let allowedDomains = "sea.demo.allowedDomains"
        static let presentation = "sea.demo.presentation"
        static let timeoutMs = "sea.demo.timeoutMs"
        static let useMockGateway = "sea.demo.useMockGateway"
        static let mockRedirectURL = "sea.demo.mockRedirectURL"
    }

    private enum Defaults {
        // Our own GatewayClient <-> local backend traffic. Not passed to SEACore.
        static let gatewayBaseURL = "http://localhost:8080"
        // Narrowing list handed to SEACore; also reused by the fuzz screen so
        // both surfaces exercise the same effective allowlist.
        static let allowedDomains = "auth.bank.local,localhost,platform-keycloak.pres.proxym-it.net"
        static let presentation = "sheet"
        static let timeoutMs = 120_000
        static let useMockGateway = true
        // A plausible local-Keycloak authorize URL. Must be https + a host in
        // the allowlist above, or SEACore's validator will reject it by design
        // (api-contract-ios-v1.md §5, rule 1 and rule 5) — that's the point of
        // the mock: it lets you exercise the WebView surface, but it does not
        // and should not bypass the core's own validation.
        // A COMPLETE, working authorize URL for the local infra/ Keycloak:
        //   - host auth.bank.local (TLS-terminated; in this app's
        //     SEASecurityConfig.plist allowlist). This host is what backs the
        //     passkey RP ID / Associated Domain (§10), so the WebView MUST load
        //     from it — not localhost — for a WebAuthn ceremony to bind. It
        //     resolves to 127.0.0.1 via the Mac's /etc/hosts (the Simulator
        //     inherits it); see infra/README.md for the one-time sudo line.
        //   - realm bankerise-mobile, client sea-dev-public (the dev-only
        //     public client — see infra/README.md)
        //   - redirect_uri bkrmob://callback — the scheme SEACore actually
        //     captures (SEASecurityConfig.plist CallbackScheme). It must match
        //     the client's registered redirectUris in provision-realm.sh.
        //   - PKCE S256 params, which sea-dev-public enforces. Omitting them
        //     makes Keycloak 302 straight to bkrmob://callback?error=…
        //     which SEA then correctly *captures* as an error-shaped callback
        //     (§6.3) instead of ever showing a login form. The challenge below
        //     is the RFC 7636 worked example (verifier
        //     dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk).
        static let mockRedirectURL =
            "https://auth.bank.local/realms/bankerise-mobile/protocol/openid-connect/auth" +
            "?client_id=sea-dev-public&redirect_uri=bkrmob%3A%2F%2Fcallback" +
            "&response_type=code&scope=openid&state=devstate123" +
            "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" +
            "&code_challenge_method=S256"
    }

    private let defaults = UserDefaults.standard

    @Published var gatewayBaseURL: String {
        didSet { defaults.set(gatewayBaseURL, forKey: Keys.gatewayBaseURL) }
    }
    @Published var allowedDomains: String {
        didSet { defaults.set(allowedDomains, forKey: Keys.allowedDomains) }
    }
    @Published var presentation: SEAPresentation {
        didSet {
            // Avoid relying on Equatable conformance for SEAPresentation (not
            // documented in the contract) — switch instead of `==`.
            let raw: String
            switch presentation {
            case .sheet: raw = "sheet"
            case .fullscreen: raw = "fullscreen"
            }
            defaults.set(raw, forKey: Keys.presentation)
        }
    }
    @Published var timeoutMs: Int {
        didSet { defaults.set(timeoutMs, forKey: Keys.timeoutMs) }
    }
    @Published var useMockGateway: Bool {
        didSet { defaults.set(useMockGateway, forKey: Keys.useMockGateway) }
    }
    @Published var mockRedirectURL: String {
        didSet { defaults.set(mockRedirectURL, forKey: Keys.mockRedirectURL) }
    }

    private init() {
        gatewayBaseURL = defaults.string(forKey: Keys.gatewayBaseURL) ?? Defaults.gatewayBaseURL
        allowedDomains = defaults.string(forKey: Keys.allowedDomains) ?? Defaults.allowedDomains
        let presentationRaw = defaults.string(forKey: Keys.presentation) ?? Defaults.presentation
        presentation = presentationRaw == "fullscreen" ? .fullscreen : .sheet
        let storedTimeout = defaults.object(forKey: Keys.timeoutMs) as? Int
        timeoutMs = storedTimeout ?? Defaults.timeoutMs
        if defaults.object(forKey: Keys.useMockGateway) != nil {
            useMockGateway = defaults.bool(forKey: Keys.useMockGateway)
        } else {
            useMockGateway = Defaults.useMockGateway
        }
        mockRedirectURL = defaults.string(forKey: Keys.mockRedirectURL) ?? Defaults.mockRedirectURL
    }

    /// Comma list -> trimmed, non-empty array, in the shape SEAConfig.allowedDomains
    /// and the fuzz screen both expect.
    var allowedDomainsArray: [String] {
        allowedDomains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
