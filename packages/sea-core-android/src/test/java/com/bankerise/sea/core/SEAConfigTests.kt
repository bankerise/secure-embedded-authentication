package com.bankerise.sea.core

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SEAConfigTests {

    @Test
    fun `default presentation is SHEET`() {
        val config = SEAConfig(
            authorizeUrl = Uri.parse("https://auth.bank.com/auth"),
            callbackScheme = "bankerise-auth"
        )
        assertEquals(SEAPresentation.SHEET, config.presentation)
    }

    @Test
    fun `default timeout is 120000ms`() {
        val config = SEAConfig(
            authorizeUrl = Uri.parse("https://auth.bank.com/auth"),
            callbackScheme = "bankerise-auth"
        )
        assertEquals(120_000L, config.timeoutMs)
    }

    @Test
    fun `default capturePolicy is WARN`() {
        val config = SEAConfig(
            authorizeUrl = Uri.parse("https://auth.bank.com/auth"),
            callbackScheme = "bankerise-auth"
        )
        assertEquals(SEACapturePolicy.WARN, config.capturePolicy)
    }

    @Test
    fun `default allowedDomains is empty`() {
        val config = SEAConfig(
            authorizeUrl = Uri.parse("https://auth.bank.com/auth"),
            callbackScheme = "bankerise-auth"
        )
        assertTrue(config.allowedDomains.isEmpty())
    }

    @Test
    fun `appearance defaults are usable`() {
        val appearance = SEAAppearance.default
        assertEquals(null, appearance.title)
        assertTrue(appearance.showsGrabber)
        assertEquals(28f, appearance.cornerRadius, 0.01f)
    }

    @Test
    fun `all fields roundtrip through data class copy`() {
        val config = SEAConfig(
            authorizeUrl = Uri.parse("https://auth.bank.com/auth"),
            callbackScheme = "bankerise-auth",
            allowedDomains = listOf("auth.bank.com"),
            presentation = SEAPresentation.FULLSCREEN,
            timeoutMs = 60_000L,
            capturePolicy = SEACapturePolicy.BLOCK_INPUT
        )
        val copy = config.copy(presentation = SEAPresentation.SHEET)
        assertEquals(SEAPresentation.SHEET, copy.presentation)
        assertEquals(60_000L, copy.timeoutMs)
        assertEquals(SEACapturePolicy.BLOCK_INPUT, copy.capturePolicy)
    }
}
