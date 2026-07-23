import Foundation

/// Mock-gateway-only PKCE authorization-code → token exchange, run straight
/// against Keycloak's token endpoint.
///
/// This exists ONLY so the demo can obtain an `id_token` to use as
/// `id_token_hint` for RP-initiated logout (see `LogoutClient`). It is NOT how
/// a real integration works — with the real gateway the exchange happens
/// server-side and the app never sees a token (§6.4), so `LoginRunner` only
/// calls this on the mock path, where the PKCE `code_verifier` is a known
/// constant (`AppSettings.mockCodeVerifier`, the RFC 7636 worked example that
/// pairs with the default mock authorize URL's `code_challenge`).
///
/// Uses an ephemeral, cookieless `URLSession`: the exchange authenticates
/// purely with `code` + `code_verifier` (public client + PKCE), so it must not
/// touch any shared cookie jar.
struct TokenExchangeClient {
    struct Tokens {
        let idToken: String
        let accessToken: String?
        let expiresIn: Int?
    }

    enum ExchangeError: Error, LocalizedError {
        case cannotDeriveEndpoint
        case httpStatus(Int, body: String)
        case decoding(String)
        case noIdToken(responseKeys: [String])

        var errorDescription: String? {
            switch self {
            case .cannotDeriveEndpoint:
                return "Could not derive the token endpoint from the authorize URL."
            case .httpStatus(let code, let body):
                return "Token endpoint returned HTTP \(code): \(body)"
            case .decoding(let detail):
                return "Failed to decode token response: \(detail)"
            case .noIdToken(let keys):
                return "Token response had no id_token (keys: \(keys.joined(separator: ", "))). "
                    + "Ensure `openid` scope is requested."
            }
        }
    }

    /// Exchanges `code` for tokens. `authorizeURL` is the exact URL SEACore
    /// loaded — its `client_id` / `redirect_uri` query params (and derived
    /// token endpoint) must match what was used to obtain the code.
    func exchange(code: String, authorizeURL: URL, codeVerifier: String) async throws -> Tokens {
        guard
            let tokenURL = authorizeURL.keycloakSiblingEndpoint("token"),
            let clientID = authorizeURL.queryValue("client_id"),
            let redirectURI = authorizeURL.queryValue("redirect_uri")
        else {
            throw ExchangeError.cannotDeriveEndpoint
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            throw ExchangeError.httpStatus(http.statusCode, body: body)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExchangeError.decoding(String(data: data, encoding: .utf8) ?? "<non-utf8>")
        }
        guard let idToken = object["id_token"] as? String else {
            throw ExchangeError.noIdToken(responseKeys: Array(object.keys))
        }
        return Tokens(
            idToken: idToken,
            accessToken: object["access_token"] as? String,
            expiresIn: object["expires_in"] as? Int
        )
    }

    /// Ephemeral + cookieless: the exchange never participates in any session
    /// cookie jar (neither the WebView's nor the native gateway's).
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()
}
