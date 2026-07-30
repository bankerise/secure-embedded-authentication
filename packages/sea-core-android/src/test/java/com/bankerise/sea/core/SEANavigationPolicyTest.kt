package com.bankerise.sea.core

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SEANavigationPolicyTest {

    private val env = SEAEnvironment(
        authDomains = setOf("auth.example.com", "localhost"),
        callbackScheme = "seacb"
    )

    // ---- Callback-scheme capture (§6.3) ----

    @Test
    fun `callback scheme capture preempts everything`() {
        val request = SEANavigationRequest(
            url = Uri.parse("seacb://callback?code=abc123&state=xyz"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Capture)
        val capture = decision as SEANavigationDecision.Capture
        assertEquals("abc123", capture.params["code"])
        assertEquals("xyz", capture.params["state"])
    }

    @Test
    fun `callback scheme capture is case insensitive`() {
        val request = SEANavigationRequest(
            url = Uri.parse("SEACB://callback?code=test"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Capture)
    }

    @Test
    fun `callback scheme captures error shaped params`() {
        val request = SEANavigationRequest(
            url = Uri.parse("seacb://callback?error=access_denied&error_description=User+denied"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Capture)
        val capture = decision as SEANavigationDecision.Capture
        assertEquals("access_denied", capture.params["error"])
        assertEquals("User denied", capture.params["error_description"])
    }

    // ---- about:blank ----

    @Test
    fun `about blank allowed for initial frame`() {
        val request = SEANavigationRequest(
            url = Uri.parse("about:blank"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertEquals(SEANavigationDecision.Allow, decision)
    }

    @Test
    fun `about blank blocked after page loads`() {
        val request = SEANavigationRequest(
            url = Uri.parse("about:blank"),
            isMainFrame = true,
            currentPageHost = "auth.example.com"
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
    }

    // ---- https + allowlist ----

    @Test
    fun `https main frame on allowlisted host allowed`() {
        val request = SEANavigationRequest(
            url = Uri.parse("https://auth.example.com/realms/test/login"),
            isMainFrame = true,
            currentPageHost = "auth.example.com"
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertEquals(SEANavigationDecision.Allow, decision)
    }

    @Test
    fun `https subresource same origin allowed`() {
        val request = SEANavigationRequest(
            url = Uri.parse("https://auth.example.com/resources/style.css"),
            isMainFrame = false,
            currentPageHost = "auth.example.com"
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertEquals(SEANavigationDecision.Allow, decision)
    }

    @Test
    fun `https subresource cross origin blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("https://localhost/resources/style.css"),
            isMainFrame = false,
            currentPageHost = "auth.example.com"
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
        assertEquals("subresource_cross_origin", (decision as SEANavigationDecision.Block).reason)
    }

    // ---- Blocked schemes ----

    @Test
    fun `http blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("http://auth.example.com/path"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
        assertEquals("scheme_not_https", (decision as SEANavigationDecision.Block).reason)
    }

    @Test
    fun `file scheme blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("file:///data/local/secret"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
    }

    @Test
    fun `intent scheme blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
    }

    @Test
    fun `javascript scheme blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("javascript:alert(document.cookie)"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
    }

    @Test
    fun `data scheme blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("data:text/html,<script>alert(1)</script>"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
    }

    // ---- Host not allowlisted ----

    @Test
    fun `host not in allowlist blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("https://evil.com/steal"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
        assertEquals("host_not_allowlisted", (decision as SEANavigationDecision.Block).reason)
    }

    @Test
    fun `missing host blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("https:///path"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
        assertEquals("missing_host", (decision as SEANavigationDecision.Block).reason)
    }

    // ---- Custom scheme (not callback) ----

    @Test
    fun `custom scheme other than callback blocked`() {
        val request = SEANavigationRequest(
            url = Uri.parse("myapp://something"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, emptyList())
        assertTrue(decision is SEANavigationDecision.Block)
    }

    // ---- Narrowed allowlist ----

    @Test
    fun `narrowed allowlist is respected`() {
        val request = SEANavigationRequest(
            url = Uri.parse("https://auth.example.com/path"),
            isMainFrame = true,
            currentPageHost = null
        )
        val decision = SEANavigationPolicy.decide(request, env, listOf("localhost"))
        assertTrue(decision is SEANavigationDecision.Block)
    }
}
