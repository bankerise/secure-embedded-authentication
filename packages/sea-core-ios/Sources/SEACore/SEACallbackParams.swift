import Foundation

/// Verbatim callback query parameters (contract §3.4, spec §6.3).
///
/// SEA performs no semantic validation of these. Error-shaped callbacks
/// (`error` + `error_description`) are delivered through `onCaptured`, not
/// `onError` — the classification of "did auth succeed" is the gateway's
/// job, not SEA's.
public struct SEACallbackParams {
    public let raw: [String: String]

    public init(raw: [String: String]) {
        self.raw = raw
    }

    public var code: String? { raw["code"] }
    public var state: String? { raw["state"] }
    public var sessionState: String? { raw["session_state"] }
    public var error: String? { raw["error"] }
    public var errorDescription: String? { raw["error_description"] }
}

extension SEACallbackParams {
    /// Extracts all query parameters from a callback URL, verbatim.
    ///
    /// Because the public type models params as `[String: String]` (per
    /// contract §3.4), a duplicated query key cannot literally retain both
    /// values — this implementation resolves duplicates last-value-wins, by
    /// walking `queryItems` in order. A key present without a value (e.g.
    /// `?foo&bar=1`) is preserved as an empty string rather than dropped, so
    /// "empty-valued keys" survive extraction as the contract's test
    /// requirements (§10) call for.
    public static func extract(from url: URL) -> SEACallbackParams {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else {
            return SEACallbackParams(raw: [:])
        }

        var raw: [String: String] = [:]
        for item in items {
            raw[item.name] = item.value ?? ""
        }
        return SEACallbackParams(raw: raw)
    }
}
