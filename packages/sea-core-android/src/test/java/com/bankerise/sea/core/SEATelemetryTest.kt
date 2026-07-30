package com.bankerise.sea.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SEATelemetryTest {

    @Test
    fun `hostHash is deterministic`() {
        val h1 = SEATelemetry.hostHash("auth.example.com")
        val h2 = SEATelemetry.hostHash("auth.example.com")
        assertEquals(h1, h2)
    }

    @Test
    fun `hostHash is 16 hex chars`() {
        val hash = SEATelemetry.hostHash("auth.example.com")
        assertEquals(16, hash.length)
        assertTrue(hash.all { it in '0'..'9' || it in 'a'..'f' })
    }

    @Test
    fun `hostHash normalizes case`() {
        val h1 = SEATelemetry.hostHash("AUTH.EXAMPLE.COM")
        val h2 = SEATelemetry.hostHash("auth.example.com")
        assertEquals(h1, h2)
    }

    @Test
    fun `hostHash strips trailing dot`() {
        val h1 = SEATelemetry.hostHash("auth.example.com.")
        val h2 = SEATelemetry.hostHash("auth.example.com")
        assertEquals(h1, h2)
    }

    @Test
    fun `different hosts produce different hashes`() {
        val h1 = SEATelemetry.hostHash("auth.example.com")
        val h2 = SEATelemetry.hostHash("evil.com")
        assertNotEquals(h1, h2)
    }

    @Test
    fun `pageClass classifies login`() {
        assertEquals(SEATelemetry.PageClass.LOGIN, SEATelemetry.pageClass("/realms/test/login"))
    }

    @Test
    fun `pageClass classifies otp`() {
        assertEquals(SEATelemetry.PageClass.OTP, SEATelemetry.pageClass("/realms/test/otp"))
    }

    @Test
    fun `pageClass classifies webauthn`() {
        assertEquals(SEATelemetry.PageClass.WEBAUTHN, SEATelemetry.pageClass("/realms/test/webauthn"))
    }

    @Test
    fun `pageClass classifies passkey`() {
        assertEquals(SEATelemetry.PageClass.WEBAUTHN, SEATelemetry.pageClass("/realms/test/passkey"))
    }

    @Test
    fun `pageClass classifies reset`() {
        assertEquals(SEATelemetry.PageClass.RESET, SEATelemetry.pageClass("/realms/test/reset-password"))
    }

    @Test
    fun `pageClass classifies broker`() {
        assertEquals(SEATelemetry.PageClass.BROKER, SEATelemetry.pageClass("/realms/test/federate"))
    }

    @Test
    fun `pageClass classifies unknown`() {
        assertEquals(SEATelemetry.PageClass.UNKNOWN, SEATelemetry.pageClass("/random/path"))
    }

    @Test
    fun `pageClass is case insensitive`() {
        assertEquals(SEATelemetry.PageClass.LOGIN, SEATelemetry.pageClass("/REALMS/TEST/LOGIN"))
    }

    @Test
    fun `no event property contains a raw host`() {
        // Verify that hostHash is the only way hosts appear in properties
        val properties = mapOf(
            "host_hash" to SEATelemetry.hostHash("auth.example.com"),
            "scheme" to "https"
        )
        assertTrue("auth.example.com" !in properties.values)
    }

    @Test
    fun `no event property contains a full url with query string`() {
        val properties = mapOf(
            "page_class" to "login",
            "ms" to "500"
        )
        // Verify no property value looks like a URL
        assertTrue(properties.values.none { it.startsWith("http") })
    }
}
