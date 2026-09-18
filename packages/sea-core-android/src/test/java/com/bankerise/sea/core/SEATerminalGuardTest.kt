package com.bankerise.sea.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SEATerminalGuardTest {

    @Test
    fun `fires once`() {
        val guard = SEATerminalGuard()
        var count = 0
        guard.fireOnce { count++ }
        assertEquals(1, count)
        assertTrue(guard.hasFired)
    }

    @Test
    fun `second call is no-op`() {
        val guard = SEATerminalGuard()
        var count = 0
        guard.fireOnce { count++ }
        guard.fireOnce { count++ }
        guard.fireOnce { count++ }
        assertEquals(1, count)
    }

    @Test
    fun `fireOnce returns true on first call`() {
        val guard = SEATerminalGuard()
        assertTrue(guard.fireOnce { })
    }

    @Test
    fun `fireOnce returns false on subsequent calls`() {
        val guard = SEATerminalGuard()
        guard.fireOnce { }
        assertFalse(guard.fireOnce { })
        assertFalse(guard.fireOnce { })
    }

    @Test
    fun `hasFired is false initially`() {
        val guard = SEATerminalGuard()
        assertFalse(guard.hasFired)
    }
}
