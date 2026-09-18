package com.bankerise.sea.core

import android.net.Uri

/**
 * Verbatim callback query parameters (contract §3.4, spec §6.3).
 *
 * SEA performs no semantic validation of these. Error-shaped callbacks
 * (`error` + `error_description`) are delivered through `onCaptured`, not
 * `onError` — the classification of "did auth succeed" is the gateway's
 * job, not SEA's.
 */
data class SEACallbackParams(val raw: Map<String, String>) {
    val code: String? get() = raw["code"]
    val state: String? get() = raw["state"]
    val sessionState: String? get() = raw["session_state"]
    val error: String? get() = raw["error"]
    val errorDescription: String? get() = raw["error_description"]

    companion object {
        /**
         * Extracts all query parameters from a callback [uri], verbatim.
         *
         * Because the public type models params as [Map]<String, String> (per
         * contract §3.4), a duplicated query key cannot literally retain both
         * values — this implementation resolves duplicates last-value-wins, by
         * iterating `uri.queryParameterNames` in order. A key present without
         * a value is preserved as an empty string rather than dropped, so
         * "empty-valued keys" survive extraction as the contract's test
         * requirements (§10) call for.
         */
        fun extract(uri: Uri): SEACallbackParams {
            val raw = mutableMapOf<String, String>()
            for (name in uri.queryParameterNames) {
                // getQueryParameter returns null for keys without values (?foo&bar=1)
                raw[name] = uri.getQueryParameter(name) ?: ""
            }
            return SEACallbackParams(raw.toMap())
        }
    }
}
