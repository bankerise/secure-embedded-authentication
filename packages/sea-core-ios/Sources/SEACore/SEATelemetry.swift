import Foundation
import CryptoKit

/// Phase-1 telemetry event names (contract §3.6, spec §20.1).
public enum SEATelemetryEventName {
    public static let webviewOpened = "AUTH_WEBVIEW_OPENED"
    public static let pageLoaded = "AUTH_PAGE_LOADED"
    public static let navBlocked = "AUTH_NAV_BLOCKED"
    public static let completed = "AUTH_COMPLETED"
    public static let cancelled = "AUTH_CANCELLED"
    public static let failed = "AUTH_FAILED"
    public static let timeout = "AUTH_TIMEOUT"
    public static let captureDetected = "AUTH_CAPTURE_DETECTED"
    public static let logoutCompleted = "AUTH_LOGOUT_COMPLETED"

    /// §10.4 step 4: the WebAuthn fallback ceremony was engaged. Carries
    /// `reason: preflight|runtime` (spec §20.1) so rollout dashboards show
    /// the embedded-vs-fallback ratio per OS version.
    public static let webauthnFallback = "AUTH_WEBAUTHN_FALLBACK"
}

/// Telemetry redaction helpers (contract §20.2 — normative and CI-tested).
///
/// Never record usernames, passwords, tokens, codes, cookies, or full URLs
/// with query strings. Hostnames are SHA-256 hashed and truncated to 16 hex
/// characters. Paths are recorded only as a coarse `page_class` bucket, never
/// as raw path strings.
public enum SEATelemetry {
    /// SHA-256 hash of an ASCII-lowercased host, truncated to 16 hex
    /// characters. This is the *only* sanctioned way a host may appear in a
    /// telemetry event property.
    public static func hostHash(_ host: String) -> String {
        let normalized = SEAEnvironment.normalizeHost(host)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// Coarse page classification bucket (spec §20.1 `AUTH_PAGE_LOADED.page_class`).
    public enum PageClass: String {
        case login, otp, webauthn, reset, broker, unknown
    }

    /// Buckets a URL path into a coarse `page_class`. The raw path itself is
    /// never retained or emitted.
    public static func pageClass(forPath path: String) -> PageClass {
        let lower = path.lowercased()
        if lower.contains("webauthn") || lower.contains("passkey") { return .webauthn }
        if lower.contains("otp") || lower.contains("totp") || lower.contains("mfa") { return .otp }
        if lower.contains("reset") || lower.contains("forgot") || lower.contains("credential") { return .reset }
        if lower.contains("broker") || lower.contains("federat") { return .broker }
        if lower.contains("login") || lower.contains("auth") { return .login }
        return .unknown
    }

    /// Routes an event to `SEASession.telemetrySink`, on the main thread,
    /// only if a sink is registered.
    static func record(name: String, properties: [String: String] = [:]) {
        SEAThread.assertMain()
        guard let sink = SEASession.telemetrySink else { return }
        sink.record(SEAEvent(name: name, properties: properties))
    }
}
