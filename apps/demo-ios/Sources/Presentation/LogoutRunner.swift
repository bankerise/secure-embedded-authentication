import Foundation

/// Drives the Config screen's "Logout" button. Branches on the same
/// `useMockGateway` toggle as login:
///
///  - **Mock**: RP-initiated logout straight against Keycloak using the
///    `id_token` obtained after the last mock login (`SessionTokenStore`).
///    Invalidates the SSO session server-side; then clears local token state.
///  - **Real**: `POST /gw/logout`; surfaces the enriched Keycloak logout URL
///    the gateway returns, to be invoked separately from this app.
///
/// Glue only — no security logic. Purging the WebView's own data store remains
/// a separate concern (the "Purge web data" button); logout here is about the
/// *server-side* Keycloak session.
@MainActor
final class LogoutRunner: ObservableObject {
    @Published var isLoggingOut = false
    @Published var message: String?
    /// Set only on the real-gateway path: the logout URL to call separately.
    @Published var gatewayLogoutURL: String?

    private let settings: AppSettings
    private let tokenStore: SessionTokenStore

    init(settings: AppSettings = .shared, tokenStore: SessionTokenStore = .shared) {
        self.settings = settings
        self.tokenStore = tokenStore
    }

    func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        message = nil
        gatewayLogoutURL = nil

        Task {
            defer { isLoggingOut = false }
            do {
                if settings.useMockGateway {
                    try await logoutMock()
                } else {
                    try await logoutReal()
                }
            } catch {
                message = "Logout failed: "
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            }
        }
    }

    private func logoutMock() async throws {
        guard let idToken = tokenStore.idToken, let authorizeURL = tokenStore.authorizeURL else {
            message = "No id_token yet — complete a mock login first."
            return
        }
        try await LogoutClient().keycloakLogout(idToken: idToken, authorizeURL: authorizeURL)
        message = "Keycloak SSO session invalidated via id_token_hint."
        tokenStore.clear()
    }

    private func logoutReal() async throws {
        guard let baseURL = URL(string: settings.gatewayBaseURL) else {
            message = "Invalid gateway base URL."
            return
        }
        let logoutURL = try await LogoutClient().gatewayLogout(baseURL: baseURL)
        gatewayLogoutURL = logoutURL
        message = "Gateway returned a logout URL — call it separately from the app."
    }
}
