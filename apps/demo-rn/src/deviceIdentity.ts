/**
 * A per-process device identifier for the real gateway's `X-Device-ID`
 * header (mirrors apps/demo-ios/Sources/Networking/DeviceIdentity.swift).
 *
 * Simplification vs. the iOS demo: generated once per app launch rather
 * than persisted (no AsyncStorage/UserDefaults-equivalent dependency in
 * this bridge-validation harness) — fine here since this header is a
 * demo-harness-only concern with no bearing on SEACore's own security
 * posture.
 */
let cached: string | undefined;

export function currentDeviceId(): string {
  if (!cached) {
    cached = `rn-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }
  return cached;
}
