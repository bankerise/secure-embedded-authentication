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
import android.view.MotionEvent
import android.view.VelocityTracker
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
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
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

        /** Downward drag past this fraction of the sheet's height dismisses it. */
        private const val DISMISS_DISTANCE_FRACTION = 0.35f

        /** Or a downward fling at/past this velocity (dp/s) dismisses it,
         *  regardless of how far it was actually dragged. */
        private const val DISMISS_FLING_VELOCITY_DP_PER_S = 800f

        /**
         * Shared duration/easing for every sheet motion — drag-dismiss,
         * drag-cancel snap-back, and (via sea_slide_up/down.xml, which use
         * the matching @interpolator/sea_sheet_motion curve) the
         * open/programmatic-close window transition. One curve everywhere
         * so the sheet reads as a single consistent motion system rather
         * than several independently-tuned animations, mirroring iOS's
         * single system-driven sheet-presentation animation.
         */
        private const val SHEET_ANIM_MS = 300L
        private val SHEET_MOTION_INTERPOLATOR = android.view.animation.PathInterpolator(0.4f, 0f, 0.2f, 1f)

        /** Height of the always-present top drag-to-dismiss zone (§18.1) —
         *  separate from the header so dragging works identically whether
         *  or not a title/header is shown. */
        private const val DRAG_ZONE_HEIGHT_DP = 32

        /**
         * A WebView's very first navigation in a process can spuriously fail
         * with ERROR_HOST_LOOKUP (net::ERR_NAME_NOT_RESOLVED) before
         * Chromium's underlying network stack has finished initializing —
         * unrelated to any real DNS/connectivity problem, and gone by the
         * very next attempt. This is a delay before the one silent retry
         * (see onReceivedError), giving that init a moment to finish rather
         * than immediately re-racing it.
         */
        private const val HOST_LOOKUP_RETRY_DELAY_MS = 400L
    }
    private val terminalGuard = SEATerminalGuard()
    private val handler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null
    private var hasFinishedFirstLoad = false
    private var hasRetriedAfterHostLookupFailure = false
    private var suppressNextPageFinished = false
    private var hostLookupRetryRunnable: Runnable? = null
    private var suppressFlagResetRunnable: Runnable? = null
    private var currentDisplayedError: SEAError? = null
    private var currentPageHost: String? = null
    private var loadStartDate: Long = 0L
    private var hasCaptured = false

    lateinit var webView: WebView
        private set
    /** `null` for a sheet with no title (§18.1) — the header is omitted
     *  entirely rather than shown empty. Always set for fullscreen. */
    var toolbar: LinearLayout? = null
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
     *
     * Fullscreen has no sheet edge to drag and no backdrop to tap outside
     * of, so — unlike [createSheetView] — it keeps an explicit close button
     * in its header; [onDismiss] fires when it's tapped.
     */
    fun createView(parent: ViewGroup, onDismiss: () -> Unit): View {
        container = LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            // §18.1: background comes from host config (mirrors iOS's
            // `view.backgroundColor = config.appearance.headerBackground`
            // in SEAAuthViewController), not hardcoded.
            setBackgroundColor(config.appearance.headerBackground)
        }

        val fullscreenToolbar = createToolbar(parent, showsCloseButton = true, onClose = onDismiss)
        toolbar = fullscreenToolbar
        container.addView(fullscreenToolbar)

        val overlay = createOverlay(parent)
        container.addView(overlay)

        // targetSdk 35+ enforces edge-to-edge by default, under which
        // windowSoftInputMode="adjustResize" (set in the manifest) alone no
        // longer reliably resizes the window around the keyboard. Padding
        // the WebView's container by the live IME inset shrinks its
        // rendered viewport instead, so the WebView's own "scroll focused
        // field into view" behavior can bring the field above the keyboard.
        applyImeInsetPadding(overlay)

        return container
    }

    /**
     * Applies bottom padding to [view] equal to the current IME (keyboard)
     * inset, live-updated as the keyboard shows/hides. Falls back to the
     * system bars' bottom inset when the keyboard is hidden, so this never
     * removes padding the OS itself expects reserved (nav bar, etc.).
     */
    private fun applyImeInsetPadding(view: View) {
        ViewCompat.setOnApplyWindowInsetsListener(view) { v, insets ->
            val imeBottom = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            val systemBarsBottom = insets.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
            v.updatePadding(bottom = maxOf(imeBottom, systemBarsBottom))
            insets
        }
        ViewCompat.requestApplyInsets(view)
    }

    /**
     * Build the bottom-sheet view hierarchy (§18.1).
     *
     * Wraps the WebView (+ header, only when a title is configured) in a
     * rounded-corner sheet that slides up from the bottom. No backdrop
     * dimming and no close button — [onDismiss] fires when the user drags
     * the sheet's top drag zone downward past the dismiss threshold, taps
     * outside the sheet's bounds, or triggers system back
     * ([handleBackPress] / [onUserDismiss]).
     */
    fun createSheetView(parent: ViewGroup, onDismiss: () -> Unit): View {
        val sheetRoot = createSheetRoot(parent)
        val sheet = createSheetContainer(parent)
        container = sheet

        // The drag zone is always present — it, not the header, is the
        // drag-to-dismiss surface (§18.1), so dragging keeps working
        // identically whether or not a header is shown below it.
        val dragZone = createDragZone(parent)
        sheet.addView(dragZone)

        // No title -> no header at all (§18.1): an empty toolbar is just
        // dead space with nothing to show, since the sheet already has no
        // close button of its own. Only reserve the header's height when
        // there's an actual title to put in it.
        val hasTitle = !config.appearance.title.isNullOrBlank()
        if (hasTitle) {
            val sheetToolbar = createToolbar(parent, showsCloseButton = false, onClose = onDismiss, heightDp = 52)
            toolbar = sheetToolbar
            sheet.addView(sheetToolbar)
        }

        val overlay = createOverlay(parent)
        sheet.addView(overlay)
        // Missing here previously: the fullscreen path already padded its
        // WebView container for the live IME inset (see applyImeInsetPadding
        // above); the sheet path never did, so the keyboard could cover the
        // focused field with nothing to scroll it back into view against.
        applyImeInsetPadding(overlay)
        sheetRoot.addView(sheet)

        // Swallow taps that land within the sheet's own bounds so they
        // don't bubble up to sheetRoot's tap-outside-to-dismiss listener
        // below (defensive — the sheet's children already fill 100% of its
        // height and consume their own touches, but this guarantees it).
        sheet.setOnClickListener { }
        sheetRoot.setOnClickListener { onDismiss() }

        // Drag handle is the top drag zone only — never the header/title —
        // so it never competes with the WebView's own touch/scroll handling
        // and keeps working even when the header is omitted above.
        attachDragToDismiss(dragZone, sheet, onDismiss)

        return sheetRoot
    }

    /**
     * Full-screen container that hosts and bottom-aligns the sheet.
     * Transparent, non-interactive — no dimming and no tap-to-dismiss
     * (§18.1: dismissal is drag-to-dismiss on the top drag zone, or system
     * back).
     *
     * The sheet's own height is *not* set here — [createSheetContainer]
     * uses `MATCH_PARENT` and lets this padding do the work, so the visible
     * sheet is always derived from a live layout pass rather than a
     * one-time screen-height snapshot. That matters because a snapshot
     * height can end up taller than the window's *current* available space
     * once the keyboard opens, pushing the sheet's rounded top corners
     * outside the visible/clipped area (§18.1's original bug: the sheet
     * appeared to "lose" its border radius whenever the keyboard showed).
     */
    private fun createSheetRoot(parent: ViewGroup): FrameLayout {
        return FrameLayout(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(0, dpToPx(parent, config.appearance.sheetTopOffset.toInt()), 0, 0)
        }
    }

    /**
     * The sheet's always-present top strip: hosts the grabber (if shown)
     * and is the sole drag-to-dismiss touch target (§18.1) — kept separate
     * from the header so the gesture is available identically whether or
     * not a title/header is present, and so the header's own content is
     * never itself a drag target.
     */
    private fun createDragZone(parent: ViewGroup): FrameLayout {
        return FrameLayout(parent.context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(parent, DRAG_ZONE_HEIGHT_DP)
            )
            if (config.appearance.showsGrabber) {
                addView(
                    createGrabber(parent),
                    FrameLayout.LayoutParams(
                        dpToPx(parent, 40), dpToPx(parent, 4), Gravity.CENTER
                    )
                )
            }
        }
    }

    /**
     * Attaches a downward-drag-to-dismiss gesture to [handle] (the sheet's
     * top drag zone — see [createDragZone]). Deliberately restricted to
     * that zone rather than the whole sheet so it never intercepts the
     * WebView's own touch/scroll handling, and deliberately *not* the
     * header, so dismissing never depends on whether a title is shown.
     *
     * Downward drag translates [sheet] by the drag distance, clamped so it
     * can never be dragged upward past its resting position. On release,
     * [onDismissed] fires — after animating the sheet fully off-screen —
     * if the drag passed [DISMISS_DISTANCE_FRACTION] of the sheet's height
     * or the release velocity passed [DISMISS_FLING_VELOCITY_DP_PER_S];
     * otherwise the sheet animates back to its resting position using the
     * same [SHEET_MOTION_INTERPOLATOR] curve as the open/close window
     * transition (sea_slide_up/down.xml), so every sheet motion — open,
     * close, drag-dismiss, and snap-back — reads as one consistent system.
     */
    private fun attachDragToDismiss(handle: View, sheet: View, onDismissed: () -> Unit) {
        var velocityTracker: VelocityTracker? = null
        var startY = 0f

        handle.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    sheet.animate().cancel()
                    startY = event.rawY
                    velocityTracker = VelocityTracker.obtain().apply { addMovement(event) }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    velocityTracker?.addMovement(event)
                    val dragDistance = (event.rawY - startY).coerceAtLeast(0f)
                    sheet.translationY = dragDistance
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    var flingVelocity = 0f
                    velocityTracker?.let { tracker ->
                        tracker.addMovement(event)
                        tracker.computeCurrentVelocity(1000)
                        flingVelocity = tracker.yVelocity
                        tracker.recycle()
                    }
                    velocityTracker = null

                    val density = handle.resources.displayMetrics.density
                    val flingThresholdPx = DISMISS_FLING_VELOCITY_DP_PER_S * density
                    val distanceThresholdPx = sheet.height * DISMISS_DISTANCE_FRACTION

                    val shouldDismiss = sheet.translationY > distanceThresholdPx ||
                        flingVelocity > flingThresholdPx
                    if (shouldDismiss) {
                        sheet.animate()
                            .translationY(sheet.height.toFloat())
                            .setInterpolator(SHEET_MOTION_INTERPOLATOR)
                            .setDuration(SHEET_ANIM_MS)
                            .withEndAction { onDismissed() }
                            .start()
                    } else {
                        sheet.animate()
                            .translationY(0f)
                            .setInterpolator(SHEET_MOTION_INTERPOLATOR)
                            .setDuration(SHEET_ANIM_MS)
                            .start()
                    }
                    true
                }
                else -> false
            }
        }
    }

    /**
     * `cornerRadius` (like every other appearance dimension here) is
     * specified in dp — matching iOS's `SEAAppearance.cornerRadius`, which
     * is in points and so is already automatically screen-density-correct.
     * `Outline.setRoundRect`/`GradientDrawable.cornerRadii` both want raw
     * pixels, so this converts once via [dpToPxF] rather than passing the
     * dp number straight through — using it unconverted previously meant
     * the configured radius rendered far smaller than intended on anything
     * but a 1x-density screen.
     */
    private fun createSheetContainer(parent: ViewGroup): LinearLayout {
        val cornerRadiusPx = dpToPxF(parent, config.appearance.cornerRadius)
        return LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            // MATCH_PARENT, not a precomputed pixel height: this view's
            // *parent* (createSheetRoot) already reserves sheetTopOffset via
            // padding, so this always fills exactly whatever height is
            // actually available right now — including after the keyboard
            // changes it — instead of a stale screen-height snapshot.
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ).apply {
                gravity = Gravity.BOTTOM
            }
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, cornerRadiusPx)
                }
            }
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(
                    cornerRadiusPx, cornerRadiusPx,
                    cornerRadiusPx, cornerRadiusPx,
                    0f, 0f, 0f, 0f
                )
                setColor(Color.WHITE)
            }
            // The outline used for `clipToOutline` above must track this
            // view's *current* bounds, or the rounded-corner clip goes
            // stale on resize — which is what reads as "the sheet lost its
            // border radius" whenever this view's live-derived height
            // above actually changes (e.g. the keyboard opening).
            addOnLayoutChangeListener { v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
                if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) {
                    v.invalidateOutline()
                }
            }
        }
    }

    private fun createGrabber(parent: ViewGroup): ImageView {
        return ImageView(parent.context).apply {
            setImageResource(R.drawable.sea_sheet_grabber)
            setColorFilter(config.appearance.closeIconTint)
        }
    }

    /**
     * @param showsCloseButton fullscreen only (§18.1) — the sheet has no
     *   close button; it dismisses via drag, tap-outside, or system back.
     * @param onClose invoked when the close button is tapped. Unused (never
     *   wired to anything) when [showsCloseButton] is false.
     * @param heightDp fullscreen keeps its original 72dp toolbar; the
     *   sheet's title bar (only ever built when there *is* a title — see
     *   [createSheetView]) uses a slimmer 52dp, closer to iOS's header.
     */
    private fun createToolbar(
        parent: ViewGroup,
        showsCloseButton: Boolean,
        onClose: () -> Unit,
        heightDp: Int = 72
    ): LinearLayout {
        return LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(parent, heightDp)
            )

            titleTextView = TextView(parent.context).apply {
                text = config.appearance.title
                setTextColor(config.appearance.headerText)
                textSize = 18f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
            addView(titleTextView, LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                marginStart = dpToPx(parent, 16)
                marginEnd = dpToPx(parent, 16)
                gravity = Gravity.CENTER_VERTICAL
            })

            if (showsCloseButton) {
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
                        marginEnd = dpToPx(parent, 8)
                        topMargin = dpToPx(parent, 4)
                        bottomMargin = dpToPx(parent, 4)
                    }

                    setOnClickListener { onClose() }
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
        // If the sheet is dismissed mid-retry (see onReceivedError's
        // ERROR_HOST_LOOKUP handling), these must not fire after webView is
        // destroyed below.
        hostLookupRetryRunnable?.let { handler.removeCallbacks(it) }
        hostLookupRetryRunnable = null
        suppressFlagResetRunnable?.let { handler.removeCallbacks(it) }
        suppressFlagResetRunnable = null
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

    /**
     * User dismissed the surface via any path — fullscreen's toolbar close
     * button; the sheet's drag-to-dismiss or tap-outside; or system back on
     * either — fires the appropriate terminal callback exactly once so the
     * host always observes the dismissal and can reset its state.
     */
    fun onUserDismiss() {
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
            if (suppressNextPageFinished) {
                suppressNextPageFinished = false
                suppressFlagResetRunnable?.let { handler.removeCallbacks(it) }
                suppressFlagResetRunnable = null
                Log.d(TAG, "onPageFinished: suppressed (paired with the host-lookup retry's failed attempt)")
                return
            }
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

                // Check backstop after page finishes
                if (url != null) {
                    checkCallbackBackstop(Uri.parse(url))
                }
            }
        }

        override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
            if (request?.isForMainFrame != true) return

            // See HOST_LOOKUP_RETRY_DELAY_MS: a spurious first-navigation
            // DNS failure, not a real error. Retry once, silently — the
            // loading spinner is already showing and stays showing, so
            // nothing is visibly different to the user beyond a short delay.
            if (error?.errorCode == WebViewClient.ERROR_HOST_LOOKUP &&
                !hasRetriedAfterHostLookupFailure && !hasFinishedFirstLoad
            ) {
                hasRetriedAfterHostLookupFailure = true
                Log.d(TAG, "onReceivedError: ERROR_HOST_LOOKUP on first navigation, retrying once")

                // WebView pairs a main-frame onReceivedError with a
                // subsequent onPageFinished for that same failed
                // navigation. Without suppressing it, that spurious call
                // would consume onPageFinished's one-shot
                // hasFinishedFirstLoad guard before the retry below even
                // starts — leaving the retry's own (real) onPageFinished
                // silently ignored and the loading spinner stuck forever.
                // Self-clears shortly after the retry starts in case a
                // given WebView build doesn't pair them 1:1, so this can
                // never permanently swallow a genuine page-finished event.
                suppressNextPageFinished = true
                suppressFlagResetRunnable?.let { handler.removeCallbacks(it) }
                suppressFlagResetRunnable = Runnable { suppressNextPageFinished = false }
                handler.postDelayed(suppressFlagResetRunnable!!, HOST_LOOKUP_RETRY_DELAY_MS * 2)

                hostLookupRetryRunnable = Runnable { retryLoad() }
                handler.postDelayed(hostLookupRetryRunnable!!, HOST_LOOKUP_RETRY_DELAY_MS)
                return
            }

            handleNavigationFailure(error?.description?.toString() ?: "Unknown error")
        }

        override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
            // §9.2: always cancel. No user override, no debug bypass in release.
            handler?.cancel()
        }
    }

    // ---- WebChromeClient ----

    private fun createChromeClient(): WebChromeClient = object : WebChromeClient() {
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

    // ---- Helpers ----

    private fun dpToPx(view: android.view.View, dp: Int): Int {
        val density = view.resources.displayMetrics.density
        return (dp * density + 0.5f).toInt()
    }

    private fun dpToPxF(view: android.view.View, dp: Float): Float {
        return dp * view.resources.displayMetrics.density
    }
}
