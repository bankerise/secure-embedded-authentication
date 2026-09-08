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
 * Runner selection for the auth surface (contract §3.1, spec §10.4).
 * Mirrors `SEAAuthMode` in `sea-core-ios`'s `SEAConfig.swift`.
 *
 * [EMBEDDED] (default) is the normal SEA path: embedded WebView, falling
 * back to [NATIVE_BROWSER] automatically only if the pre-flight WebAuthn
 * capability probe ([SEAWebAuthnCapability]) reports the embedded ceremony
 * is unsupported on this OS.
 *
 * [NATIVE_BROWSER] is a caller-selected override that skips the embedded
 * path entirely and hands the whole login attempt to the external-browser
 * fallback ([SEAFallbackAuthRunner]) up front — the same fallback runner
 * §10.4 already uses, just entered deliberately instead of via the
 * capability probe.
 */
enum class SEAAuthMode {
    EMBEDDED,
    NATIVE_BROWSER
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

    /** Custom scheme the callback redirect uses, e.g. "myapp-auth". */
    val callbackScheme: String,

    /** Host-supplied allowlist. Narrowing only (§7.1) — intersected with the
     *  compiled [SEAEnvironment.authDomains], never widening it. */
    val allowedDomains: List<String> = emptyList(),

    val presentation: SEAPresentation = SEAPresentation.SHEET,
    val appearance: SEAAppearance = SEAAppearance.default,

    /** Overall session timeout in milliseconds. Default 120_000 (§3.1). */
    val timeoutMs: Long = 120_000L,

    /** Screen-recording capture policy (§8 / spec §17.1). Default [SEACapturePolicy.WARN]. */
    val capturePolicy: SEACapturePolicy = SEACapturePolicy.WARN,

    /**
     * Allowed ports for the authorize URL (§6.2).
     * -1 means the port is unset (standard HTTPS). Default: setOf(-1, 443).
     */
    val allowedPorts: Set<Int> = setOf(-1, 443),

    /**
     * Maximum byte length of the authorize URL string (§6.2).
     * URLs exceeding this are rejected. Default: 2048.
     */
    val maxUrlLengthBytes: Int = 2048,

    /**
     * Allowed URI schemes for the authorize URL (§6.2).
     * Default: setOf("https"). Add "http" for local dev with TLS termination
     * at a reverse proxy (never in production).
     */
    val allowedSchemes: Set<String> = setOf("https"),

    /** Runner selection (spec §10.4). Default [SEAAuthMode.EMBEDDED]. */
    val authMode: SEAAuthMode = SEAAuthMode.EMBEDDED
)
