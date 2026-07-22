import Foundation

/// WebAuthn-in-`WKWebView` pre-flight capability probe (spec §10.4 step 1,
/// "pre-flight: OS/WebView version below floor").
///
/// Pure and dependency-free (no UIKit, no I/O) so it is directly
/// unit-testable: the decision is a single OS-version comparison against a
/// named floor constant.
///
/// **SPIKE-PROVISIONAL** (spec §10.2 engineering note, §25 "Compatibility
/// Matrix — to be finalized in platform spike"): the exact iOS version at
/// which WKWebView WebAuthn for app-associated domains becomes reliable has
/// not yet been validated by the platform spike. `iOS 16.0` is today's
/// best-guess floor. It is deliberately kept as a single named constant
/// (`embeddedSupportFloor`) so it can be corrected the moment the spike
/// produces a validated number, without touching any call site.
public enum SEAWebAuthnCapability {
    /// Spike-provisional floor (§10.2, §25) below which the embedded
    /// WKWebView WebAuthn ceremony is not considered supported. Adjust only
    /// here once the platform spike confirms the real floor.
    public static let embeddedSupportFloor = OperatingSystemVersion(
        majorVersion: 16,
        minorVersion: 0,
        patchVersion: 0
    )

    /// Whether the embedded WKWebView WebAuthn ceremony is expected to work
    /// on `osVersion`.
    ///
    /// Defaults to the real running OS version
    /// (`ProcessInfo.processInfo.operatingSystemVersion`), but the parameter
    /// is injectable so unit tests can force either branch deterministically
    /// — independent of whatever OS version actually runs the test — and so
    /// callers can validate the fallback path end-to-end on a modern
    /// Simulator/device by passing a below-floor version explicitly.
    public static func isEmbeddedCeremonySupported(
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        isVersion(osVersion, atLeast: embeddedSupportFloor)
    }

    /// Pure `OperatingSystemVersion` comparison (major, then minor, then
    /// patch). `internal`, not `private`, so it is directly testable without
    /// needing to fake `ProcessInfo`.
    static func isVersion(_ version: OperatingSystemVersion, atLeast floor: OperatingSystemVersion) -> Bool {
        if version.majorVersion != floor.majorVersion {
            return version.majorVersion > floor.majorVersion
        }
        if version.minorVersion != floor.minorVersion {
            return version.minorVersion > floor.minorVersion
        }
        return version.patchVersion >= floor.patchVersion
    }
}
