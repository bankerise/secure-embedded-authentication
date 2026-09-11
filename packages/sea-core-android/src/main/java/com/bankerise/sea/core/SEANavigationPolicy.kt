package com.bankerise.sea.core

import android.net.Uri

/**
 * Outcome of a navigation decision (contract §6 — normative).
 */
sealed class SEANavigationDecision {
    /**
     * The navigating URL matched [SEASession.Callbacks]'s callback scheme.
     * The navigation MUST be cancelled and never dispatched to the OS;
     * [params] is the verbatim query-parameter extraction.
     */
    data class Capture(val params: Map<String, String>) : SEANavigationDecision()

    /** The navigation is permitted to proceed. */
    object Allow : SEANavigationDecision()

    /**
     * The navigation MUST be cancelled. [reason] is a coarse, non-PII
     * symbolic string — it never contains a raw host or URL, so it is
     * always safe to fold directly into telemetry alongside a separately
     * computed `host_hash`.
     */
    data class Block(val reason: String) : SEANavigationDecision()
}

/**
 * Everything the navigation policy needs to know about one navigation
 * request. Constructing this from [android.webkit.WebViewClient] callbacks
 * is the delegate's only job — the decision itself lives here.
 */
data class SEANavigationRequest(
    val url: Uri,
    val isMainFrame: Boolean,
    /** Host of the frame's currently-committed page, normalized. `null` when
     *  nothing has committed yet (the initial load). */
    val currentPageHost: String?
)

/**
 * Navigation policy (contract §6, spec §7.3 — normative).
 *
 * A pure, synchronous decision function taking a URL + frame info and
 * returning a [SEANavigationDecision]. `WebViewClient` is a thin
 * caller of this — all the interesting logic (and all the interesting
 * tests) live here, off the Android WebView runtime.
 *
 * Evaluated in this exact order, fail closed on any ambiguity:
 * 1. Callback-scheme match preempts everything → [SEANavigationDecision.Capture].
 * 2. `about:blank` for the initial frame → [SEANavigationDecision.Allow].
 * 3. `https` + host in the effective allowlist + (main frame OR
 *    same-origin subresource) → [SEANavigationDecision.Allow].
 * 4. Everything else → [SEANavigationDecision.Block].
 */
object SEANavigationPolicy {

    fun decide(
        request: SEANavigationRequest,
        env: SEAEnvironment,
        hostAllowlist: List<String>
    ): SEANavigationDecision {
        val scheme = request.url.scheme?.lowercase() ?: ""

        // 1. Callback-scheme match preempts everything, including malformed
        //    or otherwise-suspicious URLs — it never reaches the OS.
        if (scheme.isNotEmpty() && scheme == env.callbackScheme.lowercase()) {
            val params = SEACallbackParams.extract(request.url)
            return SEANavigationDecision.Capture(params.raw)
        }

        // 2. about:blank for the initial frame (main frame, nothing committed
        //    yet) is allowed — this is the WebView-internal blank document,
        //    not attacker-controlled content.
        if (request.isMainFrame &&
            request.currentPageHost == null &&
            request.url.toString().lowercase() == "about:blank"
        ) {
            return SEANavigationDecision.Allow
        }

        // 3. https + allowlisted host + (main frame or same-origin subresource).
        if (scheme != "https") {
            return SEANavigationDecision.Block(reason = "scheme_not_https")
        }

        val rawHost = request.url.host
        if (rawHost.isNullOrEmpty()) {
            return SEANavigationDecision.Block(reason = "missing_host")
        }
        val host = SEAEnvironment.normalizeHost(rawHost)
        val effectiveAllowlist = env.effectiveAllowlist(hostAllowlist)
        if (host !in effectiveAllowlist) {
            return SEANavigationDecision.Block(reason = "host_not_allowlisted")
        }

        if (request.isMainFrame) {
            return SEANavigationDecision.Allow
        }

        // Subresource loads must additionally be same-origin as the
        // currently-committed page — being in the allowlist is necessary but
        // not sufficient for a subresource, since a main-frame navigation may
        // legitimately hop between allowlisted domains (e.g. broker IdPs)
        // while a subresource load should not be able to pull content
        // cross-origin between two otherwise-allowlisted domains.
        val currentHost = request.currentPageHost
        if (currentHost != null && currentHost == host) {
            return SEANavigationDecision.Allow
        }
        return SEANavigationDecision.Block(reason = "subresource_cross_origin")
    }
}
