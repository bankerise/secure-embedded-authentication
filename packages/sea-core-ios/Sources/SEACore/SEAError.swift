import Foundation

/// SEA's error taxonomy (contract §3.5, spec §7.2).
public enum SEAError: Error, Equatable {
    case network(underlying: String)
    case timeout
    case cancelled
    case invalidAuthorizeURL(reason: SEAInvalidURLReason)
    case serverError(statusCode: Int)

    /// Phase 2 (§10). Passkeys/WebAuthn are out of scope for Phase 1. This
    /// case is declared to keep the cross-bridge error taxonomy stable but is
    /// never thrown by this package in Phase 1.
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
