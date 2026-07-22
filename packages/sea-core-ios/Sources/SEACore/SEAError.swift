import Foundation

/// SEA's error taxonomy (contract §3.5, spec §7.2).
public enum SEAError: Error, Equatable {
    case network(underlying: String)
    case timeout
    case cancelled
    case invalidAuthorizeURL(reason: SEAInvalidURLReason)
    case serverError(statusCode: Int)

    /// §10.4: the WebAuthn fallback path itself could not be started. This
    /// is *not* thrown just because the embedded WKWebView ceremony is
    /// unsupported or fails live — that case is handled transparently by
    /// routing the whole login attempt through `SEAFallbackAuthRunner`
    /// (`ASWebAuthenticationSession`), which still resolves via the normal
    /// `onCaptured`/`onCancelled`/`onError` contract. This case is reachable
    /// only when the fallback itself cannot run, e.g.
    /// `SEAEnvironment.current.callbackScheme` is empty (fail-closed host
    /// misconfiguration, contract §3.3) — there is no scheme an
    /// `ASWebAuthenticationSession` could ever be started with.
    case webauthnUnavailable

    /// Phase 2 (§21). Kill-switch fallback is a Bankerise-SDK-level concern
    /// (gateway-driven `authMode`), not something SEA itself decides. This
    /// case is declared for taxonomy stability but is never thrown by this
    /// package in Phase 1.
    case killSwitched
}

/// Reasons an authorize URL fails validation (contract §3.5, §5).
///
/// Conforms to `Error` (not shown in the contract's code block) because
/// `SEAAuthorizeURLValidator.validate` returns `Result<URL, SEAInvalidURLReason>`
/// (contract §5), and `Result`'s failure type must conform to `Error`.
public enum SEAInvalidURLReason: String, Error {
    case scheme
    case host
    case userinfo
    case port
    case length
    case malformed
}
