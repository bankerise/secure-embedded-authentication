package com.bankerise.sea.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SEAScreenSecurityTests {

    @Test
    fun `not captured never produces overlay regardless of policy`() {
        for (policy in SEACapturePolicy.entries) {
            assertEquals(
                SEACaptureAction.None,
                SEAScreenSecurity.evaluateAction(isCaptured = false, policy = policy),
                "policy=$policy"
            )
        }
    }

    @Test
    fun `captured with LOG policy produces no overlay`() {
        assertEquals(
            SEACaptureAction.None,
            SEAScreenSecurity.evaluateAction(isCaptured = true, policy = SEACapturePolicy.LOG)
        )
    }

    @Test
    fun `captured with WARN policy produces non-blocking overlay`() {
        val action = SEAScreenSecurity.evaluateAction(
            isCaptured = true,
            policy = SEACapturePolicy.WARN
        )
        assertEquals(SEACaptureAction.Overlay(blocksInput = false), action)
    }

    @Test
    fun `captured with BLOCK_INPUT policy produces blocking overlay`() {
        val action = SEAScreenSecurity.evaluateAction(
            isCaptured = true,
            policy = SEACapturePolicy.BLOCK_INPUT
        )
        assertEquals(SEACaptureAction.Overlay(blocksInput = true), action)
    }
}
