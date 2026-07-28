package com.bankerise.sea.core

import org.junit.Assert.*
import org.junit.Test

class SEAWebAuthnLiveFailureTest {

    @Test
    fun `indicatesWebauthnUnavailable returns true for webauthn_error`() {
        val params = SEACallbackParams(raw = mapOf("error" to "webauthn_error"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns true for not_allowed_error`() {
        val params = SEACallbackParams(raw = mapOf("error" to "not_allowed_error"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns true for not_supported_error`() {
        val params = SEACallbackParams(raw = mapOf("error" to "not_supported_error"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns true for security_error`() {
        val params = SEACallbackParams(raw = mapOf("error" to "security_error"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns true for webauthn_unsupported`() {
        val params = SEACallbackParams(raw = mapOf("error" to "webauthn_unsupported"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `indicatesWebauthnUnavailable is case insensitive`() {
        val params = SEACallbackParams(raw = mapOf("error" to "WEBAUTHN_ERROR"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))

        val params2 = SEACallbackParams(raw = mapOf("error" to "WebAuthn_Error"))
        assertTrue(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params2))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns false for unrelated errors`() {
        val params = SEACallbackParams(raw = mapOf("error" to "access_denied"))
        assertFalse(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))

        val params2 = SEACallbackParams(raw = mapOf("error" to "invalid_request"))
        assertFalse(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params2))

        val params3 = SEACallbackParams(raw = mapOf("error" to "server_error"))
        assertFalse(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params3))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns false when error is null`() {
        val params = SEACallbackParams(raw = mapOf("code" to "some_code"))
        assertFalse(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `indicatesWebauthnUnavailable returns false when error is empty`() {
        val params = SEACallbackParams(raw = mapOf("error" to ""))
        assertFalse(SEAWebAuthnLiveFailure.indicatesWebauthnUnavailable(params))
    }

    @Test
    fun `webauthnErrorSignals contains expected values`() {
        val expectedSignals = setOf(
            "webauthn_error",
            "not_allowed_error",
            "not_supported_error",
            "security_error",
            "webauthn_unsupported"
        )
        assertEquals(expectedSignals, SEAWebAuthnLiveFailure.webauthnErrorSignals)
    }
}
