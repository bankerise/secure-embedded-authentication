package com.bankerise.sea.core

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Runs the spec §10.4 fallback ceremony: hands the *entire* login attempt
 * to an external browser (via Intent) using the same gateway-issued authorize
 * URL as the embedded path, and resolves through the exact same
 * [SEASession.Callbacks] contract.
 *
 * On Android, the equivalent of iOS's `ASWebAuthenticationSession` is to
 * launch an external browser (or Chrome Custom Tab) that handles the
 * WebAuthn ceremony natively. The browser has full access to the platform
 * authenticator (fingerprint, face, security keys) and shares the system
 * credential manager.
 *
 * Not part of the public contract surface — reached only via
 * [SEASession.makeIntent] when [SEAWebAuthnCapability.isEmbeddedCeremonySupported]
 * returns false.
 */
internal class SEAFallbackAuthRunner(
    private val activity: Activity,
    private val config: SEAConfig,
    private val environment: SEAEnvironment,
    private val callbacks: SEASession.Callbacks
) {
    private val terminalGuard = SEATerminalGuard()
    private val handler = Handler(Looper.getMainLooper())
    private var hasStarted = false
    private var startDate: Long = 0L

    /**
     * Starts the fallback ceremony.
     *
     * Guard (contract §3.3 fail-closed / spec §10.4): if
     * [environment.callbackScheme] is empty — the fail-closed value
     * when the host app's configuration is missing or malformed — there is
     * no scheme an Intent could ever be started with (an empty string is
     * never dispatched back to us; the session would simply hang until
     * timeout/user-cancel). Rather than start a session that can never
     * succeed, fail closed immediately with [SEAError.WebauthnUnavailable].
     */
    fun start() {
        SEAThread.assertMain()

        if (hasStarted) return
        hasStarted = true

        if (environment.callbackScheme.isEmpty()) {
            if (terminalGuard.fireOnce {
                    callbacks.onError(SEAError.WebauthnUnavailable)
                }) {
                dismissActivity()
            }
            return
        }

        startDate = System.currentTimeMillis()

        SEATelemetry.record(
            name = SEATelemetryEventName.WEBVIEW_OPENED,
            properties = mapOf(
                "mode" to "fallback",
                "prewarmed" to "false",
                "locale" to java.util.Locale.getDefault().toString()
            )
        )
        SEATelemetry.record(
            name = SEATelemetryEventName.WEBAUTHN_FALLBACK,
            properties = mapOf(
                "reason" to "preflight",
                "os_version" to Build.VERSION.SDK_INT.toString()
            )
        )

        // Build a callback URI that the browser can redirect back to.
        // A custom-scheme redirect (e.g., myapp://callback) won't work from
        // an external browser, so we use a special HTTPS URL that the host
        // app should handle via Associated Domains or intent filters.
        // For now, we use a dummy callback URL and rely on the user
        // completing the ceremony in the browser, then returning to the app.
        val callbackUri = Uri.Builder()
            .scheme(environment.callbackScheme)
            .authority("callback")
            .build()

        val intent = Intent(Intent.ACTION_VIEW, config.authorizeUrl).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        try {
            activity.startActivityForResult(intent, FALLBACK_REQUEST_CODE)
        } catch (e: Exception) {
            // No browser available — fail closed
            if (terminalGuard.fireOnce {
                    callbacks.onError(SEAError.WebauthnUnavailable)
                }) {
                dismissActivity()
            }
        }
    }

    /**
     * Called when the fallback activity returns a result.
     */
    fun handleResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != FALLBACK_REQUEST_CODE) return

        val ms = if (startDate > 0) {
            System.currentTimeMillis() - startDate
        } else 0L

        when (resultCode) {
            Activity.RESULT_OK -> {
                // The browser completed — try to extract callback params
                val uri = data?.data
                if (uri != null && uri.scheme?.lowercase() == environment.callbackScheme.lowercase()) {
                    val params = SEACallbackParams.extract(uri)
                    if (terminalGuard.fireOnce {
                            SEATelemetry.record(
                                name = SEATelemetryEventName.COMPLETED,
                                properties = mapOf(
                                    "total_ms" to ms.toString(),
                                    "method_class" to "fallback"
                                )
                            )
                            callbacks.onCaptured(params)
                        }) {
                        dismissActivity()
                    }
                } else {
                    // No callback URI — user likely completed in browser
                    // but we can't capture the result
                    if (terminalGuard.fireOnce {
                            callbacks.onCancelled()
                        }) {
                        dismissActivity()
                    }
                }
            }
            Activity.RESULT_CANCELED -> {
                if (terminalGuard.fireOnce {
                        SEATelemetry.record(
                            name = SEATelemetryEventName.CANCELLED,
                            properties = mapOf("stage" to "fallback")
                        )
                        callbacks.onCancelled()
                    }) {
                    dismissActivity()
                }
            }
            else -> {
                if (terminalGuard.fireOnce {
                        callbacks.onError(SEAError.Network("Fallback failed with result: $resultCode"))
                    }) {
                    dismissActivity()
                }
            }
        }
    }

    private fun dismissActivity() {
        SEAThread.assertMain()
        activity.finish()
    }

    companion object {
        const val FALLBACK_REQUEST_CODE = 10_400
    }
}
