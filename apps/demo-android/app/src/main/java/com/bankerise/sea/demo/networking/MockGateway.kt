package com.bankerise.sea.demo.networking

import android.net.Uri
import kotlinx.coroutines.delay

/**
 * Zero-network stand-in for [GatewayClient]. Returns a canned `redirectUrl`
 * (configurable, defaults to a local-Keycloak-shaped authorize URL) so the
 * WebView / navigation surface can be exercised with no backend running.
 *
 * Note this does NOT bypass SEACore's own validation — the URL still has to
 * be https and host-allowlisted, or [com.bankerise.sea.core.SEASession.start]
 * will reject it and fire `onError(.invalidAuthorizeUrl)` exactly as it would
 * for a real gateway response.
 */
class MockGateway(private val redirectUrlString: String) : AuthGateway {

    override suspend fun startAuthorization(locale: String?): GatewayStartResult {
        val uri = Uri.parse(redirectUrlString)
            ?: throw GatewayError("Malformed redirect URL: $redirectUrlString")

        // Small artificial delay so the UI loading state is visible.
        delay(250)

        return GatewayStartResult(
            redirectUrl = uri,
            authMode = "EMBEDDED",
            provider = "mock"
        )
    }
}
