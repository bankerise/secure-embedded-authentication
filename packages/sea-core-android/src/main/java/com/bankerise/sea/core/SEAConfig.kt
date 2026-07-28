package com.bankerise.sea.core

import android.net.Uri
import androidx.annotation.ColorInt

/**
 * Presentation style for the auth surface (contract §3.1, spec §18.1).
 */
enum class SEAPresentation {
    SHEET,
    FULLSCREEN
}

/**
 * Screen-recording capture policy (contract §8 / spec §17.1).
 * Default is [WARN].
 */
enum class SEACapturePolicy {
    LOG,
    WARN,
    BLOCK_INPUT
}

/**
 * Host-supplied configuration for a SEA session (contract §3.1).
 *
 * Note: `capturePolicy` is not enumerated in contract §3.1's code block but
 * is required by contract §8 / spec §17.1 ("Exposed on `SEAConfig` as
 * `capturePolicy`"). It is added here as an additive field with a default,
 * so it does not change the shape callers must supply.
 */
data class SEAConfig(
    /** Gateway-issued authorize URL (§6.1). Validated before anything loads. */
    val authorizeUrl: Uri,

    /** Custom scheme the callback redirect uses, e.g. "bankerise-auth". */
    val callbackScheme: String,

    /** Host-supplied allowlist. Narrowing only (§7.1) — intersected with the
     *  compiled [SEAEnvironment.authDomains], never widening it. */
    val allowedDomains: List<String> = emptyList(),

    val presentation: SEAPresentation = SEAPresentation.SHEET,
    val appearance: SEAAppearance = SEAAppearance.default,

    /** Overall session timeout in milliseconds. Default 120_000 (§3.1). */
    val timeoutMs: Long = 120_000L,

    /** Screen-recording capture policy (§8 / spec §17.1). Default [SEACapturePolicy.WARN]. */
    val capturePolicy: SEACapturePolicy = SEACapturePolicy.WARN
)
