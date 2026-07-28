package com.bankerise.sea.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SEAEnvironmentAllowlistTest {

    @Test
    fun `empty narrow list returns compiled set`() {
        val env = SEAEnvironment(
            authDomains = setOf("auth.bank.com", "localhost"),
            callbackScheme = "bankerise-auth"
        )
        val effective = env.effectiveAllowlist(emptyList())
        assertEquals(setOf("auth.bank.com", "localhost"), effective)
    }

    @Test
    fun `narrowing works`() {
        val env = SEAEnvironment(
            authDomains = setOf("auth.bank.com", "localhost"),
            callbackScheme = "bankerise-auth"
        )
        val effective = env.effectiveAllowlist(listOf("localhost"))
        assertEquals(setOf("localhost"), effective)
    }

    @Test
    fun `widening is impossible`() {
        val env = SEAEnvironment(
            authDomains = setOf("auth.bank.com"),
            callbackScheme = "bankerise-auth"
        )
        val effective = env.effectiveAllowlist(listOf("evil.com"))
        assertTrue(effective.isEmpty())
    }

    @Test
    fun `disjoint list yields empty set`() {
        val env = SEAEnvironment(
            authDomains = setOf("auth.bank.com"),
            callbackScheme = "bankerise-auth"
        )
        val effective = env.effectiveAllowlist(listOf("other.com", "another.com"))
        assertTrue(effective.isEmpty())
    }

    @Test
    fun `normalizeHost lowercases`() {
        assertEquals("auth.bank.com", SEAEnvironment.normalizeHost("AUTH.BANK.COM"))
    }

    @Test
    fun `normalizeHost strips trailing dot`() {
        assertEquals("auth.bank.com", SEAEnvironment.normalizeHost("auth.bank.com."))
    }

    @Test
    fun `normalizeHost handles empty string`() {
        assertEquals("", SEAEnvironment.normalizeHost(""))
    }
}
