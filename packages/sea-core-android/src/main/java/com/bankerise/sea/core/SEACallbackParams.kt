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
            // Parsed by hand: Uri.getQueryParameter returns the FIRST value of
            // a duplicated key, and getQueryParameters doesn't decode '+' as a
            // space. Here later pairs overwrite earlier ones (last-value-wins,
            // parity with iOS) and '+' decodes to a space. A key without a
            // value (?foo&bar=1) is kept as "".
            val raw = mutableMapOf<String, String>()
            val query = uri.encodedQuery ?: return SEACallbackParams(emptyMap())
            for (pair in query.split('&')) {
                if (pair.isEmpty()) continue
                val eq = pair.indexOf('=')
                val name = decode(if (eq >= 0) pair.substring(0, eq) else pair)
                if (name.isEmpty()) continue
                raw[name] = if (eq >= 0) decode(pair.substring(eq + 1)) else ""
            }
            return SEACallbackParams(raw.toMap())
        }

        private fun decode(component: String): String =
            Uri.decode(component.replace('+', ' '))
    }
}
