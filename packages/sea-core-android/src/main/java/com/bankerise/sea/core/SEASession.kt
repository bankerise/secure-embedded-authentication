package com.bankerise.sea.core

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView

/**
 * Entry point (contract §4).
 *
 * Exactly one of [Callbacks.onCaptured] / [Callbacks.onCancelled] /
 * [Callbacks.onError] fires per session, exactly once. After a terminal
 * callback fires, the presented Activity dismisses itself and all further
 * callbacks are suppressed — enforced by [SEATerminalGuard].
 */
object SEASession {

    var telemetrySink: SEATelemetrySink? = null

    /**
     * Callbacks for a single auth session. Delivered on the main thread.
     */
    class Callbacks(
        val onCaptured: (SEACallbackParams) -> Unit,
        val onCancelled: () -> Unit,
        val onError: (SEAError) -> Unit
    )

    // ---- Static callback storage ----
    // Android Activities are launched via Intent and can't hold lambda references.
    // We store callbacks in a static map keyed by Activity identity, retrieved
    // in SEAAuthActivity.onCreate.

    private var pendingCallbacks: Callbacks? = null

    internal fun takePendingCallbacks(): Callbacks? {
        val cb = pendingCallbacks
        pendingCallbacks = null
        return cb
    }

    // ---- Fallback runner storage ----
    // Used when WebAuthn embedded ceremony is unsupported (§10.4).
    private var pendingFallbackRunner: SEAFallbackAuthRunner? = null

    internal fun takePendingFallbackRunner(): SEAFallbackAuthRunner? {
        val runner = pendingFallbackRunner
        pendingFallbackRunner = null
        return runner
    }

    /**
     * Validates [config] (§6.2) and returns an [Intent] that, when launched,
     * presents the auth surface. Returns `null` if validation failed — in that
     * case [callbacks.onError] has already been called and nothing was started.
     *
     * Spec §10.4 pre-flight: if [SEAWebAuthnCapability.isEmbeddedCeremonySupported]
     * returns false, the entire login attempt is routed to the fallback path
     * ([SEAFallbackAuthRunner]) instead of the normal embedded
     * [SEAAuthActivity].
     */
    fun makeIntent(
        context: Context,
        config: SEAConfig,
        callbacks: Callbacks
    ): android.content.Intent? {
        SEAThread.assertMain()

        val environment = SEAEnvironment.current
        val validation = SEAAuthorizeURLValidator.validate(
            config.authorizeUrl, environment, config.allowedDomains
        )
        if (validation.isFailure) {
            val reason = validation.exceptionOrNull() as? InvalidUrlReason
                ?: InvalidUrlReason.MALFORMED
            callbacks.onError(SEAError.InvalidAuthorizeUrl(reason))
            return null
        }

        // Spec §10.4 step 1: pre-flight WebAuthn capability check
        if (!SEAWebAuthnCapability.isEmbeddedCeremonySupported()) {
            // Route to fallback — the Intent will launch the fallback Activity
            // which will handle the ceremony via external browser
            return SEAAuthActivity.createIntent(context, config).apply {
                putExtra(SEAAuthActivity.EXTRA_USE_FALLBACK, true)
            }
        }

        return SEAAuthActivity.createIntent(context, config)
    }

    /**
     * Convenience: validate, build, and present [SEAAuthActivity] from
     * [activity]. Returns `true` if the auth surface was launched, `false`
     * if validation failed (in which case [callbacks.onError] already fired).
     */
    fun start(
        activity: Activity,
        config: SEAConfig,
        callbacks: Callbacks
    ): Boolean {
        SEAThread.assertMain()

        val intent = makeIntent(activity, config, callbacks) ?: return false
        pendingCallbacks = callbacks

        // Check if we're using fallback path
        if (intent.getBooleanExtra(SEAAuthActivity.EXTRA_USE_FALLBACK, false)) {
            val environment = SEAEnvironment.current
            val runner = SEAFallbackAuthRunner(activity, config, environment, callbacks)
            pendingFallbackRunner = runner
            runner.start()
            return true
        }

        activity.startActivity(intent)
        if (config.presentation == SEAPresentation.SHEET) {
            activity.overridePendingTransition(R.anim.sea_slide_up, 0)
        } else {
            activity.overridePendingTransition(0, 0)
        }
        return true
    }

    /**
     * Handles the result from a fallback activity. Call this from the
     * host Activity's `onActivityResult`.
     */
    fun handleFallbackResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val runner = takePendingFallbackRunner() ?: return
        runner.handleResult(requestCode, resultCode, data)
    }

    /**
     * §11.3 step 2 (datastore purge). Steps 1 (gateway logout), 3 (native
     * cookie jar / secure storage), and 4 (`AUTH_LOGOUT_COMPLETED` emission
     * tied to the *overall* logout operation) belong to the host SDK,
     * which orchestrates all four steps together.
     */
    fun purgeWebData(context: Context, onComplete: () -> Unit) {
        SEAThread.assertMain()

        // Clear WebView data store
        WebStorage.getInstance().deleteAllData()

        // Clear cookies
        val cookieManager = CookieManager.getInstance()
        cookieManager.removeAllCookies { onComplete() }
        cookieManager.flush()
    }
}
