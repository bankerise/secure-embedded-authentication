package com.bankerise.sea.core

import android.net.Uri

/**
 * Authorize-URL integrity validation (contract §5, spec §6.2 — normative).
 *
 * Rules are evaluated in order; all must pass. This is one of the two
 * security-perimeter components (the other being [SEANavigationPolicy]) and
 * is implemented as a pure, synchronous function for exhaustive table-driven
 * testing. Any ambiguity resolves to failure — fail closed.
 */
object SEAAuthorizeURLValidator {

    /**
     * Validates [url] against [env]'s compiled allowlist, narrowed by
     * [hostAllowlist].
     *
     * @param allowedPorts ports the URL may use (-1 = unset, 443 = default HTTPS).
     * @param maxUrlLengthBytes maximum byte length of the URL string.
     * @return [Result.success] with the original URL, or
     *         [Result.failure] with the first [InvalidUrlReason] that failed.
     */
    fun validate(
        url: Uri,
        env: SEAEnvironment,
        hostAllowlist: List<String>,
        allowedPorts: Set<Int> = setOf(-1, 443),
        maxUrlLengthBytes: Int = 2048,
        allowedSchemes: Set<String> = setOf("https")
    ): Result<Uri> {
        val uriString = url.toString()

        // 1. scheme is in the allowed set (default: {"https"}).
        val scheme = url.scheme?.lowercase() ?: return Result.failure(InvalidUrlException(InvalidUrlReason.MALFORMED))
        if (scheme !in allowedSchemes) {
            return Result.failure(InvalidUrlException(InvalidUrlReason.SCHEME))
        }

        // 2. no user, no password component.
        //    Uri.getUserInfo() returns null when absent.
        if (url.userInfo != null) {
            return Result.failure(InvalidUrlException(InvalidUrlReason.USERINFO))
        }

        // 3. port is in the allowed set.
        val port = url.port
        if (port !in allowedPorts) {
            return Result.failure(InvalidUrlException(InvalidUrlReason.PORT))
        }

        // 4. absoluteString length in bytes <= maxUrlLengthBytes.
        if (uriString.toByteArray(Charsets.UTF_8).size > maxUrlLengthBytes) {
            return Result.failure(InvalidUrlException(InvalidUrlReason.LENGTH))
        }

        // 5. host is non-nil, lowercased, and a member of the effective
        //    allowlist. Exact match only — no suffix matching. A trailing dot
        //    is stripped before comparison.
        //
        //    Host source is deliberately [Uri.getHost], which returns the
        //    ASCII/punycode form the network stack actually resolves — the
        //    wire identity. Allowlisting against the wire form (contract §5)
        //    is the only choice that can't be fooled by a homograph host.
        val rawHost = url.host
        if (rawHost.isNullOrEmpty()) {
            return Result.failure(InvalidUrlException(InvalidUrlReason.HOST))
        }
        val host = SEAEnvironment.normalizeHost(rawHost)
        val effectiveAllowlist = env.effectiveAllowlist(hostAllowlist)
        if (host !in effectiveAllowlist) {
            return Result.failure(InvalidUrlException(InvalidUrlReason.HOST))
        }

        return Result.success(url)
    }
}
