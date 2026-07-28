import Foundation

/// Presentation style for the auth surface (contract §3.1, spec §18.1).
public enum SEAPresentation {
    case sheet
    case fullscreen
}

/// Runner selection for the auth surface (contract §3.1, spec §10.4).
///
/// `.embedded` (default) is the normal SEA path: embedded `WKWebView`,
/// falling back to `.nativeBrowser` automatically only if the pre-flight
/// WebAuthn capability probe (`SEAWebAuthnCapability`) reports the embedded
/// ceremony is unsupported on this OS.
///
/// `.nativeBrowser` is a caller-selected override that skips the embedded
/// path entirely and hands the *whole* login attempt to
/// `ASWebAuthenticationSession` up front — the same fallback runner §10.4
/// already uses, just entered deliberately instead of via the capability
/// probe. This is distinct from the host-SDK-level `SYSTEM_BROWSER` authMode
/// (spec §23), which bypasses SEACore entirely and runs the classic
/// pre-SEA in-app-browser flow; `.nativeBrowser` still goes through SEACore
/// and resolves via the exact same `SEASession.Callbacks` contract as
/// `.embedded`.
public enum SEAAuthMode: Equatable {
    case embedded
    case nativeBrowser
}

/// Host-supplied configuration for a SEA session (contract §3.1).
///
/// Note: `capturePolicy` is not enumerated in contract §3.1's code block but
/// is required by contract §8 / spec §17.1 ("Exposed on `SEAConfig` as
/// `capturePolicy`"). It is added here as an additive field with a default,
/// so it does not change the shape callers must supply.
public struct SEAConfig {
    /// Gateway-issued authorize URL (§6.1). Validated by `SEAAuthorizeURLValidator`
    /// before anything loads.
    public let authorizeURL: URL

    /// Host-supplied allowlist. Narrowing only (§7.1) — intersected with
    /// `SEAEnvironment.current.authDomains`, never widening it.
    public let allowedDomains: [String]

    public let presentation: SEAPresentation
    public let appearance: SEAAppearance

    /// Overall session timeout in milliseconds. Default 120_000 (§3.1).
    public let timeoutMs: Int

    /// Screen-recording capture policy (§8 / spec §17.1). Default `.warn`.
    public let capturePolicy: SEACapturePolicy

    /// Runner selection (spec §10.4). Default `.embedded`.
    public let authMode: SEAAuthMode

    public init(
        authorizeURL: URL,
        allowedDomains: [String] = [],
        presentation: SEAPresentation = .sheet,
        appearance: SEAAppearance = .default,
        timeoutMs: Int = 120_000,
        capturePolicy: SEACapturePolicy = .warn,
        authMode: SEAAuthMode = .embedded
    ) {
        self.authorizeURL = authorizeURL
        self.allowedDomains = allowedDomains
        self.presentation = presentation
        self.appearance = appearance
        self.timeoutMs = timeoutMs
        self.capturePolicy = capturePolicy
        self.authMode = authMode
    }
}
