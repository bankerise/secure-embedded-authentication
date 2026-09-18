package com.bankerise.sea.demo.networking

import android.net.Uri
import com.bankerise.sea.core.InvalidUrlReason
import com.bankerise.sea.core.SEAAuthorizeURLValidator
import com.bankerise.sea.core.SEAEnvironment

/**
 * One-tap §23.2 navigation-fuzzing corpus. Each entry is run through
 * [SEAAuthorizeURLValidator.validate] and the result (allow/block + reason)
 * is shown in the Fuzz screen.
 *
 * See the contract-ambiguity note in the iOS demo README: the Fuzz screen
 * exercises the authorize-URL validator, not the live WebViewClient — the
 * two policies should agree but are not the same code path.
 */
object FuzzCorpus {

    data class FuzzEntry(
        val label: String,
        val url: String
    )

    data class FuzzResult(
        val entry: FuzzEntry,
        val allowed: Boolean,
        val reason: InvalidUrlReason?
    )

    private val entries = listOf(
        FuzzEntry("javascript: scheme", "javascript:alert(document.cookie)"),
        FuzzEntry("intent: scheme", "intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end"),
        FuzzEntry("file: scheme", "file:///data/local/secret"),
        FuzzEntry("content: scheme", "content://media/external/images"),
        FuzzEntry("tel: scheme", "tel:+123456789"),
        FuzzEntry("mailto: scheme", "mailto:someone@example.com"),
        FuzzEntry("plain http", "http://auth-retail.demo.proxym-it.net/realms/test/login"),
        FuzzEntry("uppercase HTTP", "HTTP://auth.bank.com/auth"),
        FuzzEntry("data: scheme", "data:text/html,<script>alert(1)</script>"),
        FuzzEntry("custom scheme (not callback)", "myapp://something"),
        FuzzEntry("callback scheme as non-callback", "BANKERISE-AUTH://callback?code=stolen"),
        FuzzEntry("look-alike host", "https://evil-auth.bank.com/path"),
        FuzzEntry("extra suffix", "https://auth.bank.com.evil.io/path"),
        FuzzEntry("userinfo trick", "https://auth.bank.com@evil.io/path"),
        FuzzEntry("non-standard port", "https://auth.bank.com:8443/path"),
        FuzzEntry("oversized URL", "https://auth.bank.com/${"a".repeat(2050)}"),
        FuzzEntry("valid https", "https://auth-retail.demo.proxym-it.net/test/login"),
        FuzzEntry("localhost (dev)", "https://auth-retail.demo.proxym-it.net/realms/test/login")
    )

    fun run(env: SEAEnvironment, hostAllowlist: List<String>): List<FuzzResult> {
        return entries.map { entry ->
            val uri = Uri.parse(entry.url)
            val result = SEAAuthorizeURLValidator.validate(uri, env, hostAllowlist)
            FuzzResult(
                entry = entry,
                allowed = result.isSuccess,
                reason = result.exceptionOrNull() as? InvalidUrlReason
            )
        }
    }
}
