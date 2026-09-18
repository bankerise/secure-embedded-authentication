package com.bankerise.sea.core

/**
 * Live-failure counterpart to [SEAWebAuthnCapability]'s pre-flight probe
 * (spec §10.4 step 1, "live: ceremony JS error surfaced via Keycloak's
 * error redirect").
 *
 * **SPIKE-PROVISIONAL, and deliberately NOT wired into the live navigation
 * path** (spec §10.2 engineering note, §25): the exact shape of the
 * Keycloak error redirect that means "the embedded WebAuthn ceremony
 * itself could not run" — as opposed to, say, a user simply declining a
 * passkey prompt, or an unrelated authentication error — has not been
 * validated against a deployed Keycloak version by the platform spike.
 * Hooking an unvalidated heuristic directly into [SEAAuthDelegate]'s
 * capture path risks silently rerouting legitimate cancellations/errors
 * into an unwanted restart, which is worse than doing nothing.
 *
 * What *is* implemented and tested here is the pure decision function
 * itself, [indicatesWebauthnUnavailable], plus this documented
 * integration seam:
 *
 * - Call it from wherever the host SDK / a later SEACore change decides to
 *   inspect an [SEASession.Callbacks.onCaptured] delivery for a Keycloak
 *   error redirect (the params reaching `onCaptured` are exactly
 *   [SEACallbackParams] — see contract §3.4/§6.3, error-shaped callbacks
 *   are delivered through `onCaptured`, never `onError`).
 * - If it returns `true`, the caller is expected to emit
 *   `AUTH_WEBAUTHN_FALLBACK { reason: "runtime" }` (via
 *   [SEATelemetryEventName.WEBAUTHN_FALLBACK]) and restart the attempt
 *   through [SEAFallbackAuthRunner] using the same authorize URL, exactly
 *   as the pre-flight path does.
 * - The exact Keycloak error-parameter vocabulary below ([webauthnErrorSignals])
 *   must be confirmed against the deployed Keycloak/WebAuthn authenticator
 *   version during the platform spike (§10.2) before this is wired into
 *   the live capture path.
 */
object SEAWebAuthnLiveFailure {

    /**
     * Candidate Keycloak `error` query-param values that plausibly signal
     * "the WebAuthn ceremony itself failed" rather than an unrelated auth
     * failure or bare user cancellation. SPIKE-PROVISIONAL — confirm against
     * the deployed Keycloak version (§10.2) before relying on this list.
     */
    val webauthnErrorSignals: Set<String> = setOf(
        "webauthn_error",
        "not_allowed_error",
        "not_supported_error",
        "security_error",
        "webauthn_unsupported"
    )

    /**
     * True when [params] looks like a Keycloak error redirect specifically
     * indicating "WebAuthn ceremony unavailable", based purely on the
     * verbatim `error` field already extracted by [SEACallbackParams] — no
     * additional parsing, no web content inspection (contract §13/§14).
     *
     * Pure and synchronous: no I/O, no side effects, fully unit-testable.
     */
    @JvmStatic
    fun indicatesWebauthnUnavailable(params: SEACallbackParams): Boolean {
        val error = params.error?.lowercase() ?: return false
        return webauthnErrorSignals.contains(error)
    }
}
