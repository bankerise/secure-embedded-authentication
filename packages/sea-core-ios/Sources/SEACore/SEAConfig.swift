import Foundation

/// Presentation style for the auth surface (contract §3.1, spec §18.1).
public enum SEAPresentation {
    case sheet
    case fullscreen
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

    public init(
        authorizeURL: URL,
        allowedDomains: [String] = [],
        presentation: SEAPresentation = .sheet,
        appearance: SEAAppearance = .default,
        timeoutMs: Int = 120_000,
        capturePolicy: SEACapturePolicy = .warn
    ) {
        self.authorizeURL = authorizeURL
        self.allowedDomains = allowedDomains
        self.presentation = presentation
        self.appearance = appearance
        self.timeoutMs = timeoutMs
        self.capturePolicy = capturePolicy
    }
}
