import Foundation

/// Result of the §6.1 two-hop start sequence: the final Keycloak authorize URL
/// SEACore will validate and load, plus the mode/provider the gateway (or the
/// mock) reported.
struct GatewayStartResult {
    let redirectURL: URL
    let authMode: String   // "EMBEDDED" | "SYSTEM_BROWSER" (absent -> EMBEDDED, §21)
    let provider: String
}

enum GatewayError: Error, LocalizedError {
    case invalidBaseURL(String)
    case httpStatus(Int, body: String)
    case decoding(String)
    case malformedRedirectURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let s):
            return "Invalid gateway base URL: \(s)"
        case .httpStatus(let code, let body):
            return "Gateway returned HTTP \(code): \(body)"
        case .decoding(let detail):
            return "Failed to decode gateway response: \(detail)"
        case .malformedRedirectURL(let s):
            return "Gateway returned a malformed redirectUrl: \(s)"
        }
    }
}

/// Abstraction over "however we get a redirectUrl to hand to SEACore" — either
/// the real two-hop gateway sequence (GatewayClient) or the zero-network
/// MockGateway. The Config screen's "Use mock gateway" toggle picks which
/// implementation "Start login" uses; the rest of the app doesn't care.
protocol AuthGateway {
    func startAuthorization(locale: String?) async throws -> GatewayStartResult
}
