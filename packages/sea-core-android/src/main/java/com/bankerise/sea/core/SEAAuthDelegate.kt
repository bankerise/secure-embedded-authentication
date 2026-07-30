package com.bankerise.sea.core

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import android.graphics.Outline
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import com.google.android.material.progressindicator.CircularProgressIndicator

/**
 * Internal delegate that owns all WebView + navigation + terminal-callback
 * logic. Both [SEAAuthActivity] and [SEAAuthFragment] are thin lifecycle
 * wrappers around this.
 *
 * Not part of the public contract surface — [SEASession] returns it
 * type-erased. All security-relevant decision logic lives in
 * [SEANavigationPolicy] and [SEAAuthorizeURLValidator]; this class is a
 * thin, mostly-UI caller of both, plus terminal-callback bookkeeping.
 */
internal class SEAAuthDelegate(
    private val config: SEAConfig,
    private val environment: SEAEnvironment,
    private val callbacks: SEASession.Callbacks
) {
    companion object {
        private const val TAG = "SEAAuthDelegate"
    }
    private val terminalGuard = SEATerminalGuard()
    private val handler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null
    private var hasFinishedFirstLoad = false
    private var currentDisplayedError: SEAError? = null
    private var currentPageHost: String? = null
    private var loadStartDate: Long = 0L
    private var hasCaptured = false

    lateinit var webView: WebView
        private set
    lateinit var toolbar: LinearLayout
        private set
    lateinit var titleTextView: TextView
        private set
    lateinit var loadingView: ProgressBar
        private set
    lateinit var errorContainer: FrameLayout
        private set
    lateinit var errorTitle: TextView
        private set
    lateinit var errorMessage: TextView
        private set
    lateinit var errorRetry: TextView
        private set
    lateinit var container: LinearLayout
        private set

    /**
     * Build the full view hierarchy. Call from Activity.setContentView or
     * Fragment.onCreateView.
     */
    fun createView(parent: ViewGroup): View {
        container = LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        toolbar = createToolbar(parent)
        container.addView(toolbar)

        val overlay = createOverlay(parent)
        container.addView(overlay)

        return container
    }

    /**
     * Build the bottom-sheet view hierarchy (§18.1).
     *
     * Wraps the WebView + toolbar in a rounded-corner sheet that slides up
     * from the bottom. The [onCloseTap] callback fires when the user taps
     * the semi-transparent backdrop outside the sheet.
     */
    fun createSheetView(parent: ViewGroup, onCloseTap: () -> Unit): View {
        val backdrop = createBackdrop(parent, onCloseTap)
        val sheet = createSheetContainer(parent)
        container = sheet
        if (config.appearance.showsGrabber) sheet.addView(createGrabber(parent))
        toolbar = createToolbar(parent)
        sheet.addView(toolbar)

        val overlay = createOverlay(parent)
        sheet.addView(overlay)
        backdrop.addView(sheet)
        return backdrop
    }

    private fun createBackdrop(parent: ViewGroup, onClick: () -> Unit): FrameLayout {
        return FrameLayout(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor("#1A000000"))
            setOnClickListener { onClick() }
        }
    }

    private fun createSheetContainer(parent: ViewGroup): LinearLayout {
        val cornerRadius = config.appearance.cornerRadius
        val topOffset = dpToPx(parent, config.appearance.sheetTopOffset.toInt())
        val screenHeight = parent.resources.displayMetrics.heightPixels
        return LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                screenHeight - topOffset
            ).apply {
                gravity = Gravity.BOTTOM
            }
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, cornerRadius)
                }
            }
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(
                    cornerRadius, cornerRadius,
                    cornerRadius, cornerRadius,
                    0f, 0f, 0f, 0f
                )
                setColor(Color.WHITE)
            }
        }
    }

    private fun createGrabber(parent: ViewGroup): ImageView {
        return ImageView(parent.context).apply {
            setImageResource(R.drawable.sea_sheet_grabber)
            setColorFilter(config.appearance.closeIconTint)
            layoutParams = LinearLayout.LayoutParams(
                dpToPx(parent, 40), dpToPx(parent, 4)
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dpToPx(parent, 12)
                bottomMargin = dpToPx(parent, 8)
            }
        }
    }

    private fun createToolbar(parent: ViewGroup): LinearLayout {
        return LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(parent, 72)
            )

            // Title (weighted, single line with ellipsis)
            titleTextView = TextView(parent.context).apply {
                setTextColor(config.appearance.headerText)
                textSize = 18f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            addView(titleTextView, LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                marginStart = dpToPx(parent, 16)
                marginEnd = dpToPx(parent, 8)
                gravity = Gravity.CENTER_VERTICAL
            })

            // Close button (circular gray background, fixed at end)
            val btnSize = dpToPx(parent, 24)
            val iconInset = dpToPx(parent, 6)
            val closeBtn = android.widget.ImageButton(parent.context).apply {
                setImageDrawable(
                    InsetDrawable(
                        androidx.core.content.ContextCompat.getDrawable(
                            context, android.R.drawable.ic_menu_close_clear_cancel
                        ),
                        iconInset, iconInset, iconInset, iconInset
                    )
                )
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#E0E0E0"))
                }

                setPadding(0, 0, 0, 0)
                scaleType = ImageView.ScaleType.CENTER_INSIDE

                layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                    marginStart = dpToPx(parent, 8)
                    marginEnd = dpToPx(parent, 8)   // Padding from the right
                    topMargin = dpToPx(parent, 4)
                    bottomMargin = dpToPx(parent, 4)
                }

                setOnClickListener { headerCloseTapped() }
                contentDescription = SEAStrings.actionClose(context)
            }
            addView(closeBtn, LinearLayout.LayoutParams(
                btnSize, btnSize
            ).apply {
                marginEnd = dpToPx(parent, 8)
                gravity = Gravity.CENTER_VERTICAL
            })
        }
    }

    private fun createOverlay(parent: ViewGroup): FrameLayout {
        webView = SEAWebViewFactory.createWebView(parent.context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            webViewClient = createWebViewClient()
            webChromeClient = createChromeClient()
            // §8.2: overlay-attack mitigation — drop touches when another
            // app draws over the WebView (T10).
            filterTouchesWhenObscured = true
        }

        loadingView = com.google.android.material.progressindicator.CircularProgressIndicator(parent.context).apply {
            layoutParams = FrameLayout.LayoutParams(
                dpToPx(parent, 48), dpToPx(parent, 48),
                Gravity.CENTER
            )
            isIndeterminate = true
            indicatorSize = dpToPx(parent, 48)
            trackThickness = dpToPx(parent, 4)
            setIndicatorColor(config.appearance.accent)
        }

        errorContainer = FrameLayout(parent.context).apply {
            setBackgroundColor(Color.WHITE)
            visibility = View.GONE
        }
        val errorInner = LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        errorTitle = TextView(parent.context).apply {
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(dpToPx(parent, 24), 0, dpToPx(parent, 24), dpToPx(parent, 8))
        }
        errorMessage = TextView(parent.context).apply {
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(dpToPx(parent, 24), 0, dpToPx(parent, 24), dpToPx(parent, 16))
        }
        errorRetry = TextView(parent.context).apply {
            setTextColor(config.appearance.accent)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(dpToPx(parent, 16), dpToPx(parent, 8), dpToPx(parent, 16), dpToPx(parent, 8))
            setOnClickListener { retryLoad() }
        }
        errorInner.addView(errorTitle)
        errorInner.addView(errorMessage)
        errorInner.addView(errorRetry)
        errorContainer.addView(errorInner)

        return FrameLayout(parent.context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0, 1f
            )
            addView(webView)
            addView(loadingView)
            addView(errorContainer)
        }
    }

    fun onViewCreated() {
        val activity = container.context as? android.app.Activity
        SEAScreenSecurity.applySecureFlag(activity?.window)

        // Start screen capture monitoring (§17.1)
        activity?.let { startCaptureMonitoring(it) }

        container.viewTreeObserver.addOnGlobalLayoutListener {
            val height = container.rootView.height
            val visible = container.windowVisibility == View.VISIBLE
            // Keyboard visible detection for sheet resize (§18.1)
        }

        showLoading()
        loadStartDate = System.currentTimeMillis()
        SEATelemetry.record(
            name = SEATelemetryEventName.WEBVIEW_OPENED,
            properties = mapOf(
                "mode" to "embedded",
                "prewarmed" to "true",
                "locale" to java.util.Locale.getDefault().toString()
            )
        )

        webView.loadUrl(config.authorizeUrl.toString())
        startTimeoutTimer()
    }

    private fun startCaptureMonitoring(activity: Activity) {
        SEAScreenSecurity.startCaptureMonitoring(activity) { captured ->
            val action = SEAScreenSecurity.evaluateAction(captured, config.capturePolicy)

            if (captured) {
                val kind = if (captured) "recording" else "screenshot"
                SEATelemetry.record(
                    name = SEATelemetryEventName.CAPTURE_DETECTED,
                    properties = mapOf("kind" to kind)
                )
            }

            when (action) {
                is SEACaptureAction.None -> {
                    SEAScreenSecurity.removeCaptureOverlay(activity)
                }
                is SEACaptureAction.Overlay -> {
                    SEAScreenSecurity.installCaptureOverlay(activity, action.blocksInput)
                }
            }
        }
    }

    fun onResume() {
        val activity = container.context as? android.app.Activity
        SEAScreenSecurity.applySecureFlag(activity?.window)
    }

    fun onPause() {
        val activity = container.context as? android.app.Activity
        SEAScreenSecurity.removeSecureFlag(activity?.window)
    }

    fun onDestroy() {
        val activity = container.context as? android.app.Activity
        activity?.let { SEAScreenSecurity.stopCaptureMonitoring(it) }
        activity?.let { SEAScreenSecurity.removeCaptureOverlay(it) }
        cancelTimeout()
        webView.destroy()
    }

    fun handleBackPress(): Boolean {
        if (webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return false
    }

    // ---- Loading / error UI ----

    private fun showLoading() {
        loadingView.visibility = View.VISIBLE
        errorContainer.visibility = View.GONE
    }

    private fun hideLoading() {
        loadingView.visibility = View.GONE
    }

    private fun showError(error: SEAError) {
        currentDisplayedError = error
        hideLoading()
        val (title, message) = SEAStrings.copyFor(container.context, error)
        errorTitle.text = title
        errorMessage.text = message
        errorContainer.visibility = View.VISIBLE
        // Allow dismiss when error is shown
        (container.context as? android.app.Activity)?.let {
            // Enable swipe-to-dismiss equivalent
        }
    }

    private fun clearError() {
        currentDisplayedError = null
        errorContainer.visibility = View.GONE
    }

    private fun retryLoad() {
        clearError()
        showLoading()
        loadStartDate = System.currentTimeMillis()
        webView.loadUrl(config.authorizeUrl.toString())
        startTimeoutTimer()
    }

    // ---- Timeout ----

    private fun startTimeoutTimer() {
        cancelTimeout()
        timeoutRunnable = Runnable {
            SEATelemetry.record(
                name = SEATelemetryEventName.TIMEOUT,
                properties = mapOf("stage" to currentStage())
            )
            showError(SEAError.Timeout)
        }
        handler.postDelayed(timeoutRunnable!!, config.timeoutMs)
    }

    private fun cancelTimeout() {
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        timeoutRunnable = null
    }

    private fun currentStage(): String = when {
        hasFinishedFirstLoad -> "loaded"
        currentDisplayedError != null -> "error"
        else -> "loading"
    }

    // ---- Navigation policy application ----

    private fun applyDecision(
        decision: SEANavigationDecision,
        url: Uri,
        decisionHandler: (Boolean) -> Unit
    ) {
        Log.d(TAG, "applyDecision: decision=$decision url=$url")
        when (decision) {
            is SEANavigationDecision.Capture -> {
                decisionHandler(false)  // cancel navigation
                handleCapture(decision.params)
            }
            is SEANavigationDecision.Allow -> {
                decisionHandler(true)   // allow navigation
            }
            is SEANavigationDecision.Block -> {
                decisionHandler(false)  // cancel navigation
                emitNavBlocked(
                    scheme = url.scheme ?: "",
                    host = url.host,
                    reason = decision.reason
                )
            }
        }
    }

    private fun emitNavBlocked(scheme: String, host: String?, reason: String) {
        val properties = mutableMapOf("scheme" to scheme)
        if (host != null) {
            properties["host_hash"] = SEATelemetry.hostHash(host)
        }
        SEATelemetry.record(
            name = SEATelemetryEventName.NAV_BLOCKED,
            properties = properties
        )
    }

    // ---- Callback capture (§6.3) ----

    private fun checkCallbackBackstop(url: Uri?) {
        if (url == null) {
            Log.d(TAG, "checkCallbackBackstop: url is null")
            return
        }
        val scheme = url.scheme?.lowercase() ?: run {
            Log.d(TAG, "checkCallbackBackstop: no scheme in url=$url")
            return
        }
        Log.d(TAG, "checkCallbackBackstop: url=$url scheme=$scheme expected=${environment.callbackScheme.lowercase()}")
        if (scheme != environment.callbackScheme.lowercase()) return
        val params = SEACallbackParams.extract(url)
        Log.d(TAG, "checkCallbackBackstop: MATCH — params=$params")
        handleCapture(params.raw)
    }

    private fun handleCapture(raw: Map<String, String>) {
        if (hasCaptured) {
            Log.d(TAG, "handleCapture: already captured, ignoring")
            return
        }
        hasCaptured = true
        Log.d(TAG, "handleCapture: raw=$raw")
        fireTerminalOnce {
            val ms = if (loadStartDate > 0) {
                System.currentTimeMillis() - loadStartDate
            } else 0L
            SEATelemetry.record(
                name = SEATelemetryEventName.COMPLETED,
                properties = mapOf(
                    "total_ms" to ms.toString(),
                    "method_class" to "embedded"
                )
            )
            callbacks.onCaptured(SEACallbackParams(raw))
        }
    }

    private fun handleNavigationFailure(error: String) {
        // WebKit reports our own decidePolicyFor(.cancel) calls (callback
        // capture / navigation block) as cancelled errors. That is not a
        // real failure and must never surface as a native error state.
        if (error.contains("cancelled", ignoreCase = true)) return
        SEATelemetry.record(
            name = SEATelemetryEventName.FAILED,
            properties = mapOf("code" to "network")
        )
        showError(SEAError.Network(error))
    }

    private fun handleServerError(statusCode: Int) {
        SEATelemetry.record(
            name = SEATelemetryEventName.FAILED,
            properties = mapOf("code" to "server")
        )
        showError(SEAError.ServerError(statusCode))
    }

    // ---- Terminal callbacks (exactly one, exactly once, ever) ----

    private fun fireTerminalOnce(action: () -> Unit) {
        SEAThread.assertMain()
        val didFire = terminalGuard.fireOnce(action)
        if (!didFire) return
        dismissSelf()
    }

    private fun headerCloseTapped() {
        if (currentDisplayedError != null) {
            fireTerminalOnce {
                callbacks.onError(currentDisplayedError!!)
            }
        } else {
            fireTerminalOnce {
                SEATelemetry.record(
                    name = SEATelemetryEventName.CANCELLED,
                    properties = mapOf("stage" to currentStage())
                )
                callbacks.onCancelled()
            }
        }
    }

    private fun dismissSelf() {
        cancelTimeout()
        (container.context as? android.app.Activity)?.finish()
    }

    // ---- WebViewClient ----

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebViewClient(): WebViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
            val url = request?.url ?: return true
            val isMainFrame = request.isForMainFrame
            Log.d(TAG, "shouldOverrideUrlLoading: url=$url isMainFrame=$isMainFrame")

            val navRequest = SEANavigationRequest(
                url = url,
                isMainFrame = isMainFrame,
                currentPageHost = currentPageHost
            )
            val decision = SEANavigationPolicy.decide(
                request = navRequest,
                env = environment,
                hostAllowlist = config.allowedDomains
            )

            var allowed = false
            applyDecision(decision, url) { allowed = it }
            Log.d(TAG, "shouldOverrideUrlLoading: decision=$decision allowed=$allowed")
            return !allowed  // WebViewClient: return true = cancel, false = allow
        }

        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            // Update currentPageHost so subresource checks work (§7.3).
            if (url != null) {
                val uri = Uri.parse(url)
                val host = uri.host
                if (!host.isNullOrEmpty()) {
                    currentPageHost = SEAEnvironment.normalizeHost(host)
                }
            }
            // POST-redirect backstop (§6.3 normative): check if url matches callback scheme
            if (url != null) {
                checkCallbackBackstop(Uri.parse(url))
            }
        }

        override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
            // POST-redirect backstop (§6.3 normative)
            if (url != null) {
                checkCallbackBackstop(Uri.parse(url))
            }
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            if (!hasFinishedFirstLoad) {
                hasFinishedFirstLoad = true
                hideLoading()
                clearError()

                val ms = if (loadStartDate > 0) {
                    System.currentTimeMillis() - loadStartDate
                } else 0L
                val pageClass = SEATelemetry.pageClass(view?.url?.let { Uri.parse(it).path ?: "" } ?: "")
                SEATelemetry.record(
                    name = SEATelemetryEventName.PAGE_LOADED,
                    properties = mapOf(
                        "page_class" to pageClass.value,
                        "ms" to ms.toString()
                    )
                )

                // Update title
                updateHeaderTitle(view?.title)

                // Check backstop after page finishes
                if (url != null) {
                    checkCallbackBackstop(Uri.parse(url))
                }
            }
        }

        override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
            if (request?.isForMainFrame == true) {
                handleNavigationFailure(error?.description?.toString() ?: "Unknown error")
            }
        }

        override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
            // §9.2: always cancel. No user override, no debug bypass in release.
            handler?.cancel()
        }
    }

    // ---- WebChromeClient ----

    private fun createChromeClient(): WebChromeClient = object : WebChromeClient() {
        override fun onReceivedTitle(view: WebView?, title: String?) {
            updateHeaderTitle(title)
        }

        override fun onCreateWindow(
            view: WebView?,
            isDialog: Boolean,
            isUserGesture: Boolean,
            resultMsg: android.os.Message?
        ): Boolean {
            // §7.3: target=_blank / new-window requests: opened in the same
            // WebView if allowlisted, otherwise blocked. Never open externally.
            // Return false to deny window creation; the navigation will be
            // handled by shouldOverrideUrlLoading in the same WebView.
            return false
        }

        override fun onPermissionRequest(request: android.webkit.PermissionRequest?) {
            // §8.2: deny all media capture permissions.
            request?.deny()
        }
    }

    private fun updateHeaderTitle(title: String?) {
        val sanitized = config.appearance.title ?: SEATitleSanitizer.sanitize(title)
        titleTextView.text = sanitized
    }

    // ---- Helpers ----

    private fun dpToPx(view: android.view.View, dp: Int): Int {
        val density = view.resources.displayMetrics.density
        return (dp * density + 0.5f).toInt()
    }
}
