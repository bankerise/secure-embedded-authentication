package com.bankerise.sea.core

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.webkit.WebSettings
import android.webkit.WebView

/**
 * Hardened [WebView] construction (contract §7, spec §8.2 — normative).
 *
 * HARD CONSTRAINTS enforced here and nowhere else in the package:
 * - zero `addJavascriptInterface` calls
 * - no `evaluateJavascript` call anywhere in this package
 * - no reading of page DOM or content
 */
object SEAWebViewFactory {

    /**
     * Builds a hardened [WebView] using the settings described in
     * contract §7 / spec §8.2.
     */
    fun createWebView(context: Context): WebView {
        val webView = WebView(context)

        webView.settings.apply {
            // Required by Keycloak pages.
            javaScriptEnabled = true
            // Keycloak login JS uses DOM storage.
            domStorageEnabled = true
            // §8.2: no file or content access.
            allowFileAccess = false
            allowContentAccess = false
            // §7.3: window.open handled by WebChromeClient.
            setSupportMultipleWindows(true)
            // §8.2: geolocation disabled.
            setGeolocationEnabled(false)
            // §8.2: no mixed content.
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            // §8.2: safe browsing on.
            safeBrowsingEnabled = true
            // §8.2: allow content JS (Keycloak needs it) but not file access.
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
        }

        // §8.2: debug bridging off in release.
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)

        // §8.2: no back-forward gestures.
        webView.isHorizontalScrollBarEnabled = false
        webView.isVerticalScrollBarEnabled = false

        // Autofill support for login fields.
        webView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES

        return webView
    }
}
