package com.bankerise.sea.core

import android.app.Activity
import android.content.Intent
import android.net.Uri
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class SEAFallbackAuthRunnerTest {

    private lateinit var activity: Activity
    private lateinit var config: SEAConfig
    private lateinit var environment: SEAEnvironment
    private lateinit var callbacks: SEASession.Callbacks

    private var capturedParams: SEACallbackParams? = null
    private var cancelledCalled = false
    private var errorCalled: SEAError? = null

    @Before
    fun setup() {
        activity = mock(Activity::class.java)
        config = SEAConfig(
            authorizeUrl = Uri.parse("https://auth.bank.local/realms/bankerise-mobile/protocol/openid-connect/auth?client_id=sea-dev-public&redirect_uri=bkrmob%3A%2F%2Fcallback&response_type=code&scope=openid&state=devstate123"),
            callbackScheme = "bkrmob",
            allowedDomains = listOf("auth.bank.local")
        )
        environment = SEAEnvironment(
            authDomains = setOf("auth.bank.local"),
            callbackScheme = "bkrmob"
        )
        callbacks = SEASession.Callbacks(
            onCaptured = { capturedParams = it },
            onCancelled = { cancelledCalled = true },
            onError = { errorCalled = it }
        )
    }

    @Test
    fun `constructor stores config and callbacks`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        assertNotNull(runner)
    }

    @Test
    fun `start with empty callbackScheme fires webauthnUnavailable error`() {
        val emptySchemeEnv = SEAEnvironment(
            authDomains = setOf("auth.bank.local"),
            callbackScheme = ""
        )
        val runner = SEAFallbackAuthRunner(activity, config, emptySchemeEnv, callbacks)
        runner.start()

        assertNotNull(errorCalled)
        assertTrue(errorCalled is SEAError.WebauthnUnavailable)
        verify(activity).finish()
    }

    @Test
    fun `start with valid callbackScheme attempts to start activity`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.start()

        verify(activity).startActivityForResult(any(Intent::class.java), eq(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE))
    }

    @Test
    fun `start is idempotent`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.start()
        runner.start() // Second call should be ignored

        // Should only be called once
        verify(activity, times(1)).startActivityForResult(any(Intent::class.java), eq(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE))
    }

    @Test
    fun `handleResult with wrong request code does nothing`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(99999, Activity.RESULT_OK, null)

        assertNull(capturedParams)
        assertFalse(cancelledCalled)
        assertNull(errorCalled)
    }

    @Test
    fun `handleResult with RESULT_CANCELED fires onCancelled`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, Activity.RESULT_CANCELED, null)

        assertTrue(cancelledCalled)
        assertNull(capturedParams)
        verify(activity).finish()
    }

    @Test
    fun `handleResult with RESULT_OK and callback URI fires onCaptured`() {
        val callbackUri = Uri.parse("bkrmob://callback?code=test_code&state=test_state")
        val data = mock(Intent::class.java)
        `when`(data.data).thenReturn(callbackUri)

        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, Activity.RESULT_OK, data)

        assertNotNull(capturedParams)
        assertEquals("test_code", capturedParams?.code)
        assertEquals("test_state", capturedParams?.state)
        verify(activity).finish()
    }

    @Test
    fun `handleResult with RESULT_OK and non-callback URI fires onCancelled`() {
        val nonCallbackUri = Uri.parse("https://example.com/some/path")
        val data = mock(Intent::class.java)
        `when`(data.data).thenReturn(nonCallbackUri)

        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, Activity.RESULT_OK, data)

        assertTrue(cancelledCalled)
        assertNull(capturedParams)
        verify(activity).finish()
    }

    @Test
    fun `handleResult with RESULT_OK and null data fires onCancelled`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, Activity.RESULT_OK, null)

        assertTrue(cancelledCalled)
        assertNull(capturedParams)
        verify(activity).finish()
    }

    @Test
    fun `handleResult with unknown result code fires onError`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, 999, null)

        assertNotNull(errorCalled)
        assertTrue(errorCalled is SEAError.Network)
        verify(activity).finish()
    }

    @Test
    fun `handleResult is idempotent`() {
        val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, Activity.RESULT_CANCELED, null)
        runner.handleResult(SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE, Activity.RESULT_CANCELED, null)

        // Should only be called once
        assertTrue(cancelledCalled)
        verify(activity, times(1)).finish()
    }

    @Test
    fun `FALLBACK_REQUEST_CODE is correct value`() {
        assertEquals(10_400, SEAFallbackAuthRunner.FALLBACK_REQUEST_CODE)
    }
}
