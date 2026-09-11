package com.bankerise.sea.core

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SEACallbackParamsTest {

    @Test
    fun `extracts code and state`() {
        val uri = Uri.parse("seacb://callback?code=abc123&state=xyz")
        val params = SEACallbackParams.extract(uri)
        assertEquals("abc123", params.code)
        assertEquals("xyz", params.state)
    }

    @Test
    fun `extracts error shaped params`() {
        val uri = Uri.parse("seacb://callback?error=access_denied&error_description=User+denied")
        val params = SEACallbackParams.extract(uri)
        assertEquals("access_denied", params.error)
        assertEquals("User denied", params.errorDescription)
        assertNull(params.code)
    }

    @Test
    fun `extracts session_state`() {
        val uri = Uri.parse("seacb://callback?code=abc&session_state=active")
        val params = SEACallbackParams.extract(uri)
        assertEquals("active", params.sessionState)
    }

    @Test
    fun `empty valued key preserved`() {
        val uri = Uri.parse("seacb://callback?foo&bar=1")
        val params = SEACallbackParams.extract(uri)
        assertEquals("", params.raw["foo"])
        assertEquals("1", params.raw["bar"])
    }

    @Test
    fun `no query params returns empty map`() {
        val uri = Uri.parse("seacb://callback")
        val params = SEACallbackParams.extract(uri)
        assertTrue(params.raw.isEmpty())
    }

    @Test
    fun `duplicate keys last value wins`() {
        // This is a contract-level limitation documented in the iOS implementation.
        // Android Uri.queryParameterNames returns unique names, so duplicates
        // are naturally last-value-wins.
        val uri = Uri.parse("seacb://callback?code=first&code=second")
        val params = SEACallbackParams.extract(uri)
        assertEquals("second", params.code)
    }

    @Test
    fun `all properties accessible`() {
        val uri = Uri.parse(
            "seacb://callback?code=c&state=s&session_state=ss&e=err&error_description=desc"
        )
        val params = SEACallbackParams.extract(uri)
        assertEquals("c", params.code)
        assertEquals("s", params.state)
        assertEquals("ss", params.sessionState)
        assertEquals("err", params.error)
        assertEquals("desc", params.errorDescription)
    }
}
