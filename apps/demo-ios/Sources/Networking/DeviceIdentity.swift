import Foundation

/// A stable per-install device identifier, generated once and persisted in
/// `UserDefaults.standard`. The real gateway's hop 1 (`GET /authorization`)
/// requires an `X-Device-ID` header; this is a demo-harness-only concern and
/// has no bearing on SEACore's own security posture.
enum DeviceIdentity {
    private static let key = "sea.demo.deviceId"

    /// Reused across launches — generated once per install, not per request.
    static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}
