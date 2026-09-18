package com.bankerise.sea.demo.networking

import android.net.Uri

/**
 * Result of the §6.1 two-hop start sequence: the final Keycloak authorize URL
 * SEACore will validate and load, plus the mode/provider the gateway (or the
 * mock) reported.
 */
data class GatewayStartResult(
    val redirectUrl: Uri,
    val authMode: String,   // "EMBEDDED" | "SYSTEM_BROWSER"
    val provider: String
)

/**
 * Abstraction over "however we get a redirectUrl to hand to SEACore" — either
 * the real two-hop gateway sequence ([GatewayClient]) or the zero-network
 * [MockGateway].
 */
interface AuthGateway {
    suspend fun startAuthorization(locale: String?): GatewayStartResult
}

class GatewayError(message: String, cause: Throwable? = null) : Exception(message, cause)
