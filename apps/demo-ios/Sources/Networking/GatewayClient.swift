import Foundation

/// Real implementation of the §6.1 two-hop gateway start sequence:
///
///   1. POST {baseURL}/authorization/start  -> { redirect, authMode, provider }
///   2. GET  {redirect}                     -> { redirectUrl, provider }
///          + Set-Cookie: SESSION (pre-auth), landing in the NATIVE cookie jar
///
/// Per §6.5, the pre-auth SESSION cookie must be retained in this native jar
/// and must NEVER be handed to the WebView — SEACore's WKWebView uses its own
/// `.default()` WKWebsiteDataStore (contract §7), which is a separate cookie
/// domain entirely. This client intentionally never touches WKWebsiteDataStore
/// or shares its URLSession/cookie storage with anything WebView-related.
final class GatewayClient: AuthGateway {
    private let baseURL: URL
    private let session: URLSession

    /// A shared cookie storage + session configured to always accept cookies,
    /// so the hop-2 `Set-Cookie: SESSION` response is retained natively.
    init(baseURL: URL) {
        self.baseURL = baseURL

        let cookieStorage = HTTPCookieStorage.shared
        cookieStorage.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true

        self.session = URLSession(configuration: configuration)
    }

    convenience init?(baseURLString: String) {
        guard let url = URL(string: baseURLString) else { return nil }
        self.init(baseURL: url)
    }

    func startAuthorization(locale: String?) async throws -> GatewayStartResult {
        let startResponse = try await postAuthorizationStart(locale: locale)
        let redirectResponse = try await getRedirect(startResponse.redirect)

        guard let finalURL = URL(string: redirectResponse.redirectUrl) else {
            throw GatewayError.malformedRedirectURL(redirectResponse.redirectUrl)
        }

        return GatewayStartResult(
            redirectURL: finalURL,
            authMode: startResponse.authMode,
            provider: redirectResponse.provider
        )
    }

    // MARK: - Hop 1

    private struct StartRequestBody: Encodable {
        let locale: String?
    }

    private struct StartResponse: Decodable {
        let redirect: String
        let authMode: String
        let provider: String
    }

    private func postAuthorizationStart(locale: String?) async throws -> StartResponse {
        let url = baseURL.appendingPathComponent("authorization/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(StartRequestBody(locale: locale))

        let (data, response) = try await session.data(for: request)
        try Self.assertSuccess(response, data: data)

        do {
            return try JSONDecoder().decode(StartResponse.self, from: data)
        } catch {
            throw GatewayError.decoding("hop 1 (/authorization/start): \(error)")
        }
    }

    // MARK: - Hop 2

    private struct RedirectResponse: Decodable {
        let redirectUrl: String
        let provider: String
    }

    private func getRedirect(_ redirect: String) async throws -> RedirectResponse {
        guard let url = URL(string: redirect, relativeTo: baseURL)?.absoluteURL else {
            throw GatewayError.invalidBaseURL(redirect)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try Self.assertSuccess(response, data: data)

        do {
            return try JSONDecoder().decode(RedirectResponse.self, from: data)
        } catch {
            throw GatewayError.decoding("hop 2 (\(redirect)): \(error)")
        }
    }

    // MARK: - Helpers

    private static func assertSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
            throw GatewayError.httpStatus(http.statusCode, body: body)
        }
    }
}
