package com.bankerise.sea.core

import android.os.Build

/**
 * WebAuthn-in-WebView pre-flight capability probe (spec §10.4 step 1,
 * "pre-flight: OS/WebView version below floor").
 *
 * Pure and dependency-free (no Android framework, no I/O) so it is directly
 * unit-testable: the decision is a single OS-version comparison against a
 * named floor constant.
 *
 * **SPIKE-PROVISIONAL** (spec §10.2 engineering note, §25 "Compatibility
 * Matrix — to be finalized in platform spike"): the exact Android version at
 * which WebView WebAuthn for app-associated domains becomes reliable has
 * not yet been validated by the platform spike. `Android 8.0 (API 26)` is
 * today's best-guess floor (minSdk is 26, so this effectively means "all
 * supported devices"). It is deliberately kept as a single named constant
 * (`embeddedSupportFloor`) so it can be corrected the moment the spike
 * produces a validated number, without touching any call site.
 */
object SEAWebAuthnCapability {

    /**
     * Spike-provisional floor (§10.2, §25) below which the embedded
     * WebView WebAuthn ceremony is not considered supported. Adjust only
     * here once the platform spike confirms the real floor.
     *
     * Uses API level for comparison since Android versioning is API-level based.
     */
    const val embeddedSupportFloor = Build.VERSION_CODES.O  // API 26 (Android 8.0)

    /**
     * Whether the embedded WebView WebAuthn ceremony is expected to work
     * on the current device.
     *
     * Defaults to the real running OS version
     * (`Build.VERSION.SDK_INT`), but the parameter is injectable so unit
     * tests can force either branch deterministically — independent of
     * whatever OS version actually runs the test — and so callers can
     * validate the fallback path end-to-end on a modern emulator/device
     * by passing a below-floor version explicitly.
     */
    @JvmStatic
    @JvmOverloads
    fun isEmbeddedCeremonySupported(
        sdkVersion: Int = Build.VERSION.SDK_INT
    ): Boolean {
        return sdkVersion >= embeddedSupportFloor
    }
}
