package com.bankerise.sea.core

/**
 * SEA's error taxonomy (contract §3.5, spec §7.2).
 */
sealed class SEAError {
    data class Network(val underlying: String) : SEAError()
    object Timeout : SEAError()
    object Cancelled : SEAError()
    data class InvalidAuthorizeUrl(val reason: InvalidUrlReason) : SEAError()
    data class ServerError(val statusCode: Int) : SEAError()

    /** Phase 2 (§10). Declared for taxonomy stability; never thrown in Phase 1. */
    object WebauthnUnavailable : SEAError()

    /** Phase 2 (§21). Declared for taxonomy stability; never thrown in Phase 1. */
    object KillSwitched : SEAError()

    override fun equals(other: Any?): Boolean = when {
        this === other -> true
        other !is SEAError -> false
        else -> when (this) {
            is Network -> other is Network && underlying == other.underlying
            Timeout -> other is Timeout
            Cancelled -> other is Cancelled
            is InvalidAuthorizeUrl -> other is InvalidAuthorizeUrl && reason == other.reason
            is ServerError -> other is ServerError && statusCode == other.statusCode
            WebauthnUnavailable -> other is WebauthnUnavailable
            KillSwitched -> other is KillSwitched
        }
    }

    override fun hashCode(): Int = when (this) {
        is Network -> underlying.hashCode()
        Timeout -> 0
        Cancelled -> 1
        is InvalidAuthorizeUrl -> reason.hashCode()
        is ServerError -> statusCode
        WebauthnUnavailable -> 10
        KillSwitched -> 11
    }
}

/**
 * Reasons an authorize URL fails validation (contract §3.5, §5).
 */
enum class InvalidUrlReason {
    SCHEME,
    HOST,
    USERINFO,
    PORT,
    LENGTH,
    MALFORMED
}

class InvalidUrlException(val reason: InvalidUrlReason) : Exception(reason.name)
