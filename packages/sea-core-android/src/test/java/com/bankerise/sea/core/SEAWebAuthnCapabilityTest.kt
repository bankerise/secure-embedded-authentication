package com.bankerise.sea.core

import android.os.Build
import org.junit.Assert.*
import org.junit.Test

class SEAWebAuthnCapabilityTest {

    @Test
    fun `isEmbeddedCeremonySupported returns true for API 26 and above`() {
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.O))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.O_MR1))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.P))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.Q))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.R))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.S))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.S_V2))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.TIRAMISU))
        assertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(Build.VERSION_CODES.UPSIDE_DOWN_CAKE))
    }

    @Test
    fun `isEmbeddedCeremonySupported returns false for API below 26`() {
        assertFalse(SEAWebAuthnCapability.isEmbeddedCeremonySupported(25))
        assertFalse(SEAWebAuthnCapability.isEmbeddedCeremonySupported(24))
        assertFalse(SEAWebAuthnCapability.isEmbeddedCeremonySupported(21))
        assertFalse(SEAWebAuthnCapability.isEmbeddedCeremonySupported(1))
    }

    @Test
    fun `embeddedSupportFloor is API 26`() {
        assertEquals(Build.VERSION_CODES.O, SEAWebAuthnCapability.embeddedSupportFloor)
    }

    @Test
    fun `isEmbeddedCeremonySupported defaults to current SDK version`() {
        // This test verifies the default parameter works
        val result = SEAWebAuthnCapability.isEmbeddedCeremonySupported()
        assertEquals(result, Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
    }
}
