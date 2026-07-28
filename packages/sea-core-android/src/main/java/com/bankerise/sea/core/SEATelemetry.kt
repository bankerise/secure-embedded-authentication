package com.bankerise.sea.core

import java.security.MessageDigest

/**
 * Phase-1 telemetry event names (contract §3.6, spec §20.1).
 */
object SEATelemetryEventName {
    const val WEBVIEW_OPENED = "AUTH_WEBVIEW_OPENED"
    const val PAGE_LOADED = "AUTH_PAGE_LOADED"
    const val NAV_BLOCKED = "AUTH_NAV_BLOCKED"
    const val COMPLETED = "AUTH_COMPLETED"
    const val CANCELLED = "AUTH_CANCELLED"
    const val FAILED = "AUTH_FAILED"
    const val TIMEOUT = "AUTH_TIMEOUT"
    const val CAPTURE_DETECTED = "AUTH_CAPTURE_DETECTED"
    const val LOGOUT_COMPLETED = "AUTH_LOGOUT_COMPLETED"

    /** §10.4 step 4: the WebAuthn fallback ceremony was engaged. Carries
     *  `reason: preflight|runtime` (spec §20.1) so rollout dashboards show
     *  the embedded-vs-fallback ratio per OS version. */
    const val WEBAUTHN_FALLBACK = "AUTH_WEBAUTHN_FALLBACK"
}

/**
 * Telemetry redaction helpers (contract §20.2 — normative and CI-tested).
 *
 * Never record usernames, passwords, tokens, codes, cookies, or full URLs
 * with query strings. Hostnames are SHA-256 hashed and truncated to 16 hex
 * characters. Paths are recorded only as a coarse `page_class` bucket, never
 * as raw path strings.
 */
object SEATelemetry {

    /**
     * SHA-256 hash of an ASCII-lowered host, truncated to 16 hex
     * characters. This is the *only* sanctioned way a host may appear in a
     * telemetry event property.
     */
    fun hostHash(host: String): String {
        val normalized = SEAEnvironment.normalizeHost(host)
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(normalized.toByteArray(Charsets.UTF_8))
        val hex = digest.joinToString("") { "%02x".format(it) }
        return hex.take(16)
    }

    /**
     * Coarse page classification bucket (spec §20.1 `AUTH_PAGE_LOADED.page_class`).
     */
    enum class PageClass(val value: String) {
        LOGIN("login"),
        OTP("otp"),
        WEBAUTHN("webauthn"),
        RESET("reset"),
        BROKER("broker"),
        UNKNOWN("unknown");

        companion object {
            fun fromPath(path: String): PageClass {
                val lower = path.lowercase()
                if ("webauthn" in lower || "passkey" in lower) return WEBAUTHN
                if ("otp" in lower || "totp" in lower || "mfa" in lower) return OTP
                if ("reset" in lower || "forgot" in lower || "credential" in lower) return RESET
                if ("broker" in lower || "federat" in lower) return BROKER
                if ("login" in lower || "auth" in lower) return LOGIN
                return UNKNOWN
            }
        }
    }

    /**
     * Buckets a URL path into a coarse [PageClass]. The raw path itself is
     * never retained or emitted.
     */
    fun pageClass(path: String): PageClass = PageClass.fromPath(path)

    /**
     * Routes an event to [SEASession.telemetrySink], on the main thread,
     * only if a sink is registered.
     */
    internal fun record(name: String, properties: Map<String, String> = emptyMap()) {
        SEAThread.assertMain()
        val sink = SEASession.telemetrySink ?: return
        sink.record(SEAEvent(name = name, properties = properties))
    }
}
