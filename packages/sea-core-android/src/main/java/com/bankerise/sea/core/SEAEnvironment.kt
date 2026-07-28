package com.bankerise.sea.core

/**
 * Compiled security configuration (contract §3.3, spec §7.1/§6.2).
 *
 * [authDomains] is the build-compiled allowlist. Host-supplied
 * [SEAConfig.allowedDomains] can only narrow this set — it can never
 * widen it. This is enforced by [effectiveAllowlist], the single
 * place both the URL validator and the navigation policy compute the
 * effective set from.
 */
data class SEAEnvironment(
    val authDomains: Set<String>,
    val callbackScheme: String
) {
    init {
        // Normalize all domains at construction time.
        // (The data class copy() won't re-run init; callers must construct
        // a new SEAEnvironment if they need different domains.)
    }

    companion object {
        /**
         * Build-config-selected compiled environment.
         *
         * The concrete domains are selected by BuildConfig fields set per
         * build type in build.gradle.kts — the Android equivalent of
         * iOS's `#if SEA_ENV_PRODUCTION / SEA_ENV_STAGING / #else DEBUG`.
         *
         * `debug` adds `localhost` and `auth.bank.local` — these are
         * compiled out of any release configuration.
         */
        val current: SEAEnvironment by lazy {
            val domains = BuildConfig.COMPILED_AUTH_DOMAINS.mapTo(HashSet()) { normalizeHost(it) }
            SEAEnvironment(
                authDomains = domains,
                callbackScheme = BuildConfig.COMPILED_CALLBACK_SCHEME
            )
        }

        /**
         * Lowercases (ASCII-lowered) and strips a single trailing dot, per the
         * host-matching rules in contract §5.
         */
        fun normalizeHost(host: String): String {
            var normalized = host.lowercase()
            if (normalized.endsWith(".")) {
                normalized = normalized.dropLast(1)
            }
            return normalized
        }
    }

    /**
     * Effective allowlist per contract §3.3: host input can narrow, never
     * widen. Empty host input means "use the compiled set unchanged". A host
     * list disjoint from the compiled set yields an empty effective allowlist
     * (fail closed, not fail open).
     */
    fun effectiveAllowlist(narrowedBy: List<String>): Set<String> {
        if (narrowedBy.isEmpty()) return authDomains
        val narrowed = narrowedBy.mapTo(HashSet()) { normalizeHost(it) }
        return authDomains.intersect(narrowed)
    }
}
