import Foundation

/// Zero-network stand-in for GatewayClient. Returns a canned `redirectUrl`
/// (configurable on the Config screen, defaults to a local-Keycloak-shaped
/// authorize URL) so the WebView / navigation surface can be exercised with
/// no backend running at all.
///
/// Note this does NOT bypass SEACore's own validation (api-contract-ios-v1.md
/// §5) — the URL still has to be https and host-allowlisted, or SEASession
/// will reject it and fire onError(.invalidAuthorizeURL) exactly as it would
/// for a real gateway response. That's by design: the mock only removes the
/// network hop, not the security perimeter.
final class MockGateway: AuthGateway {
    private let redirectURLString: String

    init(redirectURLString: String) {
        self.redirectURLString = redirectURLString
    }

    func startAuthorization(locale: String?) async throws -> GatewayStartResult {
        guard let url = URL(string: redirectURLString) else {
            throw GatewayError.malformedRedirectURL(redirectURLString)
        }

        // Small artificial delay so the UI's loading state is actually visible
        // and this behaves like a real async call site.
        try? await Task.sleep(nanoseconds: 250_000_000)

        return GatewayStartResult(redirectURL: url, authMode: "EMBEDDED", provider: "mock")
    }
}
