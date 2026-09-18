package com.bankerise.sea.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SEATitleSanitizerTest {

    @Test
    fun `null returns null`() {
        assertNull(SEATitleSanitizer.sanitize(null))
    }

    @Test
    fun `empty string returns null`() {
        assertNull(SEATitleSanitizer.sanitize(""))
    }

    @Test
    fun `whitespace only returns null`() {
        assertNull(SEATitleSanitizer.sanitize("   \n\t  "))
    }

    @Test
    fun `single line preserved`() {
        assertEquals("Login to Bank", SEATitleSanitizer.sanitize("Login to Bank"))
    }

    @Test
    fun `newlines collapsed to spaces`() {
        assertEquals("Login to Bank", SEATitleSanitizer.sanitize("Login\nto\nBank"))
    }

    @Test
    fun `carriage return newlines collapsed`() {
        assertEquals("Login to Bank", SEATitleSanitizer.sanitize("Login\r\nto\r\nBank"))
    }

    @Test
    fun `trimmed`() {
        assertEquals("Login", SEATitleSanitizer.sanitize("  Login  "))
    }

    @Test
    fun `truncated at 64 chars`() {
        val longTitle = "A".repeat(100)
        val result = SEATitleSanitizer.sanitize(longTitle)
        assertEquals(64, result?.length)
    }

    @Test
    fun `exactly 64 chars preserved`() {
        val title = "A".repeat(64)
        assertEquals(title, SEATitleSanitizer.sanitize(title))
    }

    @Test
    fun `65 chars truncated to 64`() {
        val title = "A".repeat(65)
        assertEquals("A".repeat(64), SEATitleSanitizer.sanitize(title))
    }
}
