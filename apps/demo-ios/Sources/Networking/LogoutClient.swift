import Foundation

/// Two logout paths, matching the two gateway modes:
///
///  - **Mock** (`keycloakLogout`): the app holds an `id_token` (from
///    `TokenExchangeClient`), so it performs RP-initiated logout itself with a
///    cookieless GET to the end-session endpoint carrying `id_token_hint`.
///    Keycloak identifies and invalidates the SSO session purely from the
///    token — no session cookie required — which is exactly why this works
///    from the app even though the Keycloak SSO cookie lives in the WebView's
///    separate `WKWebsiteDataStore`.
///
///  - **Real** (`gatewayLogout`): the app never holds a token (§6.4), so it
///    asks the gateway (`POST /gw/logout`, carrying the native `SESSION`
///    cookie from `GatewayClient`'s shared jar) which returns the Keycloak
///    logout URL already enriched with `id_token_hint`. That URL is meant to
///    be invoked *separately* from the demo app, so this method only returns
///    it — it deliberately does not call it.
struct LogoutClient {
    enum LogoutError: Error, LocalizedError {
        case cannotDeriveEndpoint
        case httpStatus(Int, body: String)
        case noLogoutURLInResponse(body: String)

        var errorDescription: String? {
            switch self {
            case .cannotDeriveEndpoint:
                return "Could not derive the logout endpoint from the authorize URL."
            case .httpStatus(let code, let body):
                return "Logout endpoint returned HTTP \(code): \(body)"
            case .noLogoutURLInResponse(let body):
                return "Gateway /gw/logout response had no logout URL: \(body)"
            }
        }
    }

    // MARK: - Mock: direct RP-initiated logout against Keycloak

    /// Cookieless GET to `…/openid-connect/logout?id_token_hint=<idToken>`.
    /// Returns normally on any 2xx/3xx (Keycloak renders a logged-out info
    /// page); throws on 4xx/5xx.
    func keycloakLogout(idToken: String, authorizeURL: URL) async throws {
        guard let logoutBase = authorizeURL.keycloakSiblingEndpoint("logout") else {
            throw LogoutError.cannotDeriveEndpoint
        }
        guard var components = URLComponents(url: logoutBase, resolvingAgainstBaseURL: false) else {
            throw LogoutError.cannotDeriveEndpoint
        }
        components.queryItems = [URLQueryItem(name: "id_token_hint", value: idToken)]
        guard let url = components.url else { throw LogoutError.cannotDeriveEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await Self.cookielessSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            throw LogoutError.httpStatus(http.statusCode, body: body)
        }
    }

    // MARK: - Real: ask the gateway for an enriched logout URL

    /// `POST {baseURL}/gw/logout` using the shared native cookie jar (so the
    /// pre-auth/auth `SESSION` cookie set during the start hops is sent, letting
    /// the gateway resolve the session). Returns the Keycloak logout URL the
    /// gateway builds (already carrying `id_token_hint`), to be called
    /// separately from this app.
    func gatewayLogout(baseURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("gw").appendingPathComponent("logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await Self.cookieBackedSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            throw LogoutError.httpStatus(http.statusCode, body: body)
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        if let extracted = Self.extractLogoutURL(from: data, rawBody: body) {
            return extracted
        }
        throw LogoutError.noLogoutURLInResponse(body: body)
    }

    /// The exact JSON shape of `/gw/logout` isn't pinned by the contract, so be
    /// permissive: accept a JSON object under any of a few likely keys, else a
    /// bare-string body that already looks like a URL.
    private static func extractLogoutURL(from data: Data, rawBody: String) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["logoutUrl", "redirectUrl", "redirect", "url"] {
                if let value = object[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        let trimmed = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http") {
            // Handle a plain-text body, optionally wrapped in quotes.
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    // MARK: - Sessions

    /// Ephemeral + cookieless for the direct Keycloak logout — the id_token is
    /// the only credential; no cookie jar involved.
    private static let cookielessSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// Shares `HTTPCookieStorage.shared` with `GatewayClient` so the native
    /// `SESSION` cookie is carried to `/gw/logout`.
    private static let cookieBackedSession: URLSession = {
        let storage = HTTPCookieStorage.shared
        storage.cookieAcceptPolicy = .always
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = storage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }()
}
