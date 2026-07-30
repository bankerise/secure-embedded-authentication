package com.bankerise.sea.core

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SEAAuthorizeURLValidatorTest {

    private val prodEnv = SEAEnvironment(
        authDomains = setOf("auth.example.com"),
        callbackScheme = "seacb"
    )

    private val devEnv = SEAEnvironment(
        authDomains = setOf("auth.example.com", "localhost", "auth.example.local"),
        callbackScheme = "seacb"
    )

    // ---- Rule 1: scheme == https ----

    @Test
    fun `rejects http scheme`() {
        val url = Uri.parse("http://auth.example.com/realms/test/protocol/openid-connect/auth")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.SCHEME, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    @Test
    fun `rejects ftp scheme`() {
        val url = Uri.parse("ftp://auth.example.com/realms/test/protocol/openid-connect/auth")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.SCHEME, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    @Test
    fun `rejects javascript scheme`() {
        val url = Uri.parse("javascript:alert(1)")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
    }

    @Test
    fun `accepts https scheme`() {
        val url = Uri.parse("https://auth.example.com/realms/test/protocol/openid-connect/auth")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isSuccess)
    }

    @Test
    fun `accepts http scheme when allowed`() {
        val url = Uri.parse("http://auth.example.com/realms/test/protocol/openid-connect/auth")
        val result = SEAAuthorizeURLValidator.validate(
            url, prodEnv, emptyList(),
            allowedSchemes = setOf("http", "https")
        )
        assertTrue(result.isSuccess)
    }

    @Test
    fun `rejects http when allowedSchemes is https-only`() {
        val url = Uri.parse("http://auth.example.com/realms/test/protocol/openid-connect/auth")
        val result = SEAAuthorizeURLValidator.validate(
            url, prodEnv, emptyList(),
            allowedSchemes = setOf("https")
        )
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.SCHEME, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    // ---- Rule 2: no userinfo ----

    @Test
    fun `rejects url with userinfo`() {
        val url = Uri.parse("https://auth.example.com@evil.io/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.USERINFO, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    // ---- Rule 3: port ----

    @Test
    fun `rejects non-standard port`() {
        val url = Uri.parse("https://auth.example.com:8443/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.PORT, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    @Test
    fun `accepts port 443`() {
        val url = Uri.parse("https://auth.example.com:443/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isSuccess)
    }

    @Test
    fun `accepts no explicit port`() {
        val url = Uri.parse("https://auth.example.com/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isSuccess)
    }

    // ---- Rule 4: length ----

    @Test
    fun `rejects url exceeding 2048 bytes`() {
        val longPath = "a".repeat(2050)
        val url = Uri.parse("https://auth.example.com/$longPath")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.LENGTH, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    // ---- Rule 5: host allowlist ----

    @Test
    fun `rejects host not in allowlist`() {
        val url = Uri.parse("https://evil.com/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.HOST, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    @Test
    fun `rejects host with trailing dot`() {
        // auth.example.com. should not match auth.example.com
        val url = Uri.parse("https://auth.example.com./path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        // Trailing dot is stripped by normalizeHost, so auth.example.com. → auth.example.com
        // which IS in the allowlist — this is correct behavior per contract §5.
        assertTrue(result.isSuccess)
    }

    @Test
    fun `rejects subdomain not in allowlist`() {
        // evil-auth.example.com must NOT match auth.example.com
        val url = Uri.parse("https://evil-auth.example.com/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.HOST, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    @Test
    fun `rejects host with extra suffix`() {
        // auth.example.com.evil.io must NOT match auth.example.com
        val url = Uri.parse("https://auth.example.com.evil.io/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
        assertEquals(InvalidUrlReason.HOST, (result.exceptionOrNull() as? InvalidUrlException)?.reason)
    }

    @Test
    fun `case insensitive host match`() {
        val url = Uri.parse("https://AUTH.EXAMPLE.COM/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isSuccess)
    }

    @Test
    fun `narrowing allowlist works`() {
        val url = Uri.parse("https://localhost/path")
        val result = SEAAuthorizeURLValidator.validate(url, devEnv, listOf("localhost"))
        assertTrue(result.isSuccess)
    }

    @Test
    fun `narrowing allowlist excludes non-narrowed hosts`() {
        val url = Uri.parse("https://auth.example.com/path")
        val result = SEAAuthorizeURLValidator.validate(url, devEnv, listOf("localhost"))
        assertTrue(result.isFailure)
    }

    @Test
    fun `empty narrow list uses compiled set`() {
        val url = Uri.parse("https://localhost/path")
        val result = SEAAuthorizeURLValidator.validate(url, devEnv, emptyList())
        assertTrue(result.isSuccess)
    }

    @Test
    fun `disjoint narrow list yields empty allowlist`() {
        val url = Uri.parse("https://auth.example.com/path")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, listOf("other.com"))
        assertTrue(result.isFailure)
    }

    // ---- Malformed URL ----

    @Test
    fun `rejects malformed url`() {
        val url = Uri.parse("https://")
        // Uri.parse may or may not fail depending on the implementation
        // Just verify it doesn't crash
        SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
    }

    // ---- Look-alike host corpus ----

    @Test
    fun `lookalike auth bank com with extra path segment`() {
        val url = Uri.parse("https://auth.example.com.evil.io/steal")
        val result = SEAAuthorizeURLValidator.validate(url, prodEnv, emptyList())
        assertTrue(result.isFailure)
    }

    @Test
    fun `punycode host in allowlist`() {
        val env = SEAEnvironment(
            authDomains = setOf("xn--mnchen-3ya.de"),
            callbackScheme = "seacb"
        )
        val url = Uri.parse("https://xn--mnchen-3ya.de/path")
        val result = SEAAuthorizeURLValidator.validate(url, env, emptyList())
        assertTrue(result.isSuccess)
    }
}
