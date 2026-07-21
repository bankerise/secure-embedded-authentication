import Foundation

/// Real implementation of the §6.1 two-hop gateway start sequence:
///
///   1. GET {baseURL}/authorization  -> { redirect, provider }
///          (no request body; `authMode` is absent from the response and
///          defaults to "EMBEDDED" per §21 — see `startAuthorization`)
///          Headers: Accept, Accept-Language, X-App-Version-Key, X-Device-ID
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
        let startResponse = try await getAuthorizationStart()
        let redirectResponse = try await getRedirect(startResponse.redirect)

        guard let finalURL = URL(string: redirectResponse.redirectUrl) else {
            throw GatewayError.malformedRedirectURL(redirectResponse.redirectUrl)
        }

        // §21: authMode is absent from the real response entirely (not just
        // null) -> absent means EMBEDDED.
        return GatewayStartResult(
            redirectURL: finalURL,
            authMode: startResponse.authMode ?? "EMBEDDED",
            provider: redirectResponse.provider
        )
    }

    // MARK: - Hop 1

    private struct StartResponse: Decodable {
        let redirect: String
        let authMode: String?
        let provider: String
    }

    /// DEMO/TEST-ONLY value for this specific showcase environment — not a
    /// real secret, just an app-identity header the showcase gateway expects.
    private static let demoAppVersionKey = "4ZvAEYVC2Xk3"

    private func getAuthorizationStart() async throws -> StartResponse {
        let url = baseURL.appendingPathComponent("authorization")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.demoAppVersionKey, forHTTPHeaderField: "X-App-Version-Key")
        request.setValue(DeviceIdentity.current, forHTTPHeaderField: "X-Device-ID")

        let (data, response) = try await session.data(for: request)
        try Self.assertSuccess(response, data: data)

        do {
            return try JSONDecoder().decode(StartResponse.self, from: data)
        } catch {
            throw GatewayError.decoding("hop 1 (/authorization): \(error)")
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
