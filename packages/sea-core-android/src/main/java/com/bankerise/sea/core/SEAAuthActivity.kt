package com.bankerise.sea.core

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity

/**
 * The auth surface Activity (§9.1, §18.1).
 *
 * Hosts a hardened [android.webkit.WebView] in a bottom-sheet-like presentation
 * with a native toolbar (back / title / close), native loading/error states,
 * screen security, and a session timeout.
 *
 * Not part of the public contract surface — [SEASession] returns it
 * type-erased. All security-relevant decision logic lives in
 * [SEANavigationPolicy] and [SEAAuthorizeURLValidator]; this class is a
 * thin lifecycle caller of both, plus terminal-callback bookkeeping.
 *
 * Callbacks are handed off via [SEASession]'s static pending-callback
 * mechanism: [SEASession.start] stores them before launching this Activity,
 * and [onCreate] retrieves them. This avoids serializing lambdas through
 * the Intent.
 */
class SEAAuthActivity : AppCompatActivity() {

    private lateinit var delegate: SEAAuthDelegate

    companion object {
        internal const val EXTRA_AUTHORIZED_URL = "sea.auth_url"
        internal const val EXTRA_CALLBACK_SCHEME = "sea.callback_scheme"
        internal const val EXTRA_ALLOWED_DOMAINS = "sea.allowed_domains"
        internal const val EXTRA_PRESENTATION = "sea.presentation"
        internal const val EXTRA_TIMEOUT_MS = "sea.timeout_ms"
        internal const val EXTRA_CAPTURE_POLICY = "sea.capture_policy"
        internal const val EXTRA_USE_FALLBACK = "sea.use_fallback"

        fun createIntent(context: Context, config: SEAConfig): Intent {
            return Intent(context, SEAAuthActivity::class.java).apply {
                putExtra(EXTRA_AUTHORIZED_URL, config.authorizeUrl.toString())
                putExtra(EXTRA_CALLBACK_SCHEME, config.callbackScheme)
                putStringArrayListExtra(EXTRA_ALLOWED_DOMAINS, ArrayList(config.allowedDomains))
                putExtra(EXTRA_PRESENTATION, config.presentation.name)
                putExtra(EXTRA_TIMEOUT_MS, config.timeoutMs)
                putExtra(EXTRA_CAPTURE_POLICY, config.capturePolicy.name)
            }
        }

        /**
         * Reconstruct [SEAConfig] from the intent extras. Used internally
         * and by the demo app to inspect what was passed.
         */
        fun configFromIntent(intent: Intent): SEAConfig {
            val url = intent.getStringExtra(EXTRA_AUTHORIZED_URL) ?: ""
            val scheme = intent.getStringExtra(EXTRA_CALLBACK_SCHEME) ?: ""
            val domains = intent.getStringArrayListExtra(EXTRA_ALLOWED_DOMAINS) ?: emptyList()
            val presentation = try {
                SEAPresentation.valueOf(intent.getStringExtra(EXTRA_PRESENTATION) ?: "SHEET")
            } catch (_: Exception) { SEAPresentation.SHEET }
            val timeout = intent.getLongExtra(EXTRA_TIMEOUT_MS, 120_000L)
            val capturePolicy = try {
                SEACapturePolicy.valueOf(intent.getStringExtra(EXTRA_CAPTURE_POLICY) ?: "WARN")
            } catch (_: Exception) { SEACapturePolicy.WARN }

            return SEAConfig(
                authorizeUrl = android.net.Uri.parse(url),
                callbackScheme = scheme,
                allowedDomains = domains,
                presentation = presentation,
                timeoutMs = timeout,
                capturePolicy = capturePolicy
            )
        }

        /**
         * Reconstruct [SEAConfig] from individual parameters. Used by
         * [SEAAuthFragment] which stores args in a Bundle.
         */
        internal fun configFrom(
            uri: android.net.Uri,
            scheme: String,
            domains: List<String>,
            presentationRaw: String,
            timeout: Long,
            capturePolicyRaw: String
        ): SEAConfig {
            val presentation = try {
                SEAPresentation.valueOf(presentationRaw)
            } catch (_: Exception) { SEAPresentation.SHEET }
            val capturePolicy = try {
                SEACapturePolicy.valueOf(capturePolicyRaw)
            } catch (_: Exception) { SEACapturePolicy.WARN }

            return SEAConfig(
                authorizeUrl = uri,
                callbackScheme = scheme,
                allowedDomains = domains,
                presentation = presentation,
                timeoutMs = timeout,
                capturePolicy = capturePolicy
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val config = configFromIntent(intent)
        val env = SEAEnvironment(
            authDomains = config.allowedDomains.mapTo(HashSet()) { SEAEnvironment.normalizeHost(it) },
            callbackScheme = config.callbackScheme
        )

        // Check if we should use fallback path (§10.4)
        val useFallback = intent.getBooleanExtra(EXTRA_USE_FALLBACK, false)
        if (useFallback) {
            // Retrieve callbacks from SEASession's static holder.
            val userCallbacks = SEASession.takePendingCallbacks()

            // Wrap user callbacks: onCaptured/onError propagate to the user;
            // onCancelled/onError also finish() this Activity.
            val wrappedCallbacks = SEASession.Callbacks(
                onCaptured = { params ->
                    userCallbacks?.onCaptured?.invoke(params)
                },
                onCancelled = {
                    userCallbacks?.onCancelled?.invoke()
                    finishWithAnimation()
                },
                onError = { error ->
                    userCallbacks?.onError?.invoke(error)
                    finishWithAnimation()
                }
            )

            // Create and start the fallback runner
            val fallbackRunner = SEAFallbackAuthRunner(this, config, env, wrappedCallbacks)
            fallbackRunner.start()
            return
        }

        // Normal embedded path
        // Retrieve callbacks from SEASession's static holder.
        val userCallbacks = SEASession.takePendingCallbacks()

        // Wrap user callbacks: onCaptured/onError propagate to the user;
        // onCancelled/onError also finish() this Activity.
        val wrappedCallbacks = SEASession.Callbacks(
            onCaptured = { params ->
                userCallbacks?.onCaptured?.invoke(params)
            },
            onCancelled = {
                userCallbacks?.onCancelled?.invoke()
                finishWithAnimation()
            },
            onError = { error ->
                userCallbacks?.onError?.invoke(error)
                finishWithAnimation()
            }
        )

        delegate = SEAAuthDelegate(config, env, wrappedCallbacks)

        val root = FrameLayout(this)

        if (config.presentation == SEAPresentation.SHEET) {
            applySheetWindowStyle()
            val sheetView = delegate.createSheetView(root) { delegate.onUserDismiss() }
            root.addView(sheetView, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
        } else {
            val webViewContainer = delegate.createView(root)
            root.addView(webViewContainer, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
        }

        setContentView(root)
        delegate.onViewCreated()
    }

    /**
     * Apply window attributes for bottom-sheet presentation: transparent
     * background, bottom gravity, dim behind.
     */
    private fun applySheetWindowStyle() {
        window.apply {
            setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.BOTTOM)
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        }
    }

    private fun finishWithAnimation() {
        finish()
        overridePendingTransition(0, R.anim.sea_slide_down)
    }

    override fun onResume() {
        super.onResume()
        delegate.onResume()
    }

    override fun onPause() {
        super.onPause()
        delegate.onPause()
    }

    override fun onDestroy() {
        delegate.onDestroy()
        super.onDestroy()
    }

    @Deprecated("Use OnBackPressedCallback instead")
    override fun onBackPressed() {
        if (!delegate.handleBackPress()) {
            delegate.onUserDismiss()
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        // Handle fallback result (§10.4)
        SEASession.handleFallbackResult(requestCode, resultCode, data)
    }
}
