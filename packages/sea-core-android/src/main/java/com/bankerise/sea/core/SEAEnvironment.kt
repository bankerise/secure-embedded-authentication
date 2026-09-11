package com.bankerise.sea.core

/**
 * Security configuration (contract §3.3, spec §7.1/§6.2).
 *
 * Constructed at session time from host-supplied [SEAConfig]. The
 * [effectiveAllowlist] method enforces the narrowing-only rule: the host
 * allowlist is intersected with [authDomains] to produce the effective set.
 */
data class SEAEnvironment(
    val authDomains: Set<String>,
    val callbackScheme: String
) {
    companion object {
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
     * widen. Empty host input means "use the set unchanged". A host
     * list disjoint from the set yields an empty effective allowlist
     * (fail closed, not fail open).
     */
    fun effectiveAllowlist(narrowedBy: List<String>): Set<String> {
        if (narrowedBy.isEmpty()) return authDomains
        val narrowed = narrowedBy.mapTo(HashSet()) { normalizeHost(it) }
        return authDomains.intersect(narrowed)
    }
}
