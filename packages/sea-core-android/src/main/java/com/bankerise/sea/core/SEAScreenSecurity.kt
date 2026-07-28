package com.bankerise.sea.core

import android.app.Activity
import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Screen and process security (contract §8, spec §17.1).
 *
 * - [applySecureFlag]: FLAG_SECURE on the Activity/window → blocks
 *   screenshots, screen recording, and non-secure display mirroring;
 *   also blanks the recents/task-switcher thumbnail.
 * - Capture policy overlay is managed by the host Activity/Fragment
 *   (§17.1 — Android's FLAG_SECURE replaces iOS's cover-view approach
 *   for task-switcher snapshots).
 * - Screen recording detection via [ScreenCaptureCallback] (API 30+).
 */
object SEAScreenSecurity {

    private var isCaptured = false
    private var onCaptureChanged: ((Boolean) -> Unit)? = null
    private var apiHelper: CaptureMonitorHelper? = null

    /**
     * Apply FLAG_SECURE to the given window. Must be called before the
     * window is visible (typically in [Activity.onCreate] or
     * [Activity.onResume]).
     */
    fun applySecureFlag(window: Window?) {
        window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    /**
     * Remove FLAG_SECURE from the given window.
     */
    fun removeSecureFlag(window: Window?) {
        window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    /**
     * Start monitoring for screen capture (API 30+). On older APIs,
     * this is a no-op — FLAG_SECURE is the only protection available.
     *
     * @param activity The activity to monitor
     * @param onCaptureChanged Callback invoked on main thread when capture state changes
     */
    fun startCaptureMonitoring(
        activity: Activity,
        onCaptureChanged: (Boolean) -> Unit
    ) {
        this.onCaptureChanged = onCaptureChanged

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val helper = CaptureMonitorHelper(activity) { captured ->
                isCaptured = captured
                Handler(Looper.getMainLooper()).post {
                    this@SEAScreenSecurity.onCaptureChanged?.invoke(captured)
                }
            }
            apiHelper = helper
        }
    }

    /**
     * Stop monitoring for screen capture.
     */
    fun stopCaptureMonitoring(activity: Activity) {
        apiHelper?.unregister(activity)
        apiHelper = null
        onCaptureChanged = null
    }

    /**
     * Check if screen is currently being captured. Only reliable on API 30+.
     */
    fun isScreenCaptured(): Boolean = isCaptured

    /**
     * The pure decision half of screen security: given whether the screen is
     * currently being captured and the configured policy, what UI action
     * follows.
     */
    internal fun evaluateAction(isCaptured: Boolean, policy: SEACapturePolicy): SEACaptureAction {
        if (!isCaptured) return SEACaptureAction.None
        return when (policy) {
            SEACapturePolicy.LOG -> SEACaptureAction.None
            SEACapturePolicy.WARN -> SEACaptureAction.Overlay(blocksInput = false)
            SEACapturePolicy.BLOCK_INPUT -> SEACaptureAction.Overlay(blocksInput = true)
        }
    }

    /**
     * Install a capture overlay on the given window. Must be called from
     * the main thread.
     *
     * @param activity The activity to overlay
     * @param blocksInput Whether the overlay should block touch input
     * @return The overlay view, or null if already showing
     */
    fun installCaptureOverlay(activity: Activity, blocksInput: Boolean): android.view.View? {
        val window = activity.window ?: return null
        val decorView = window.decorView as? FrameLayout ?: return null

        // Check if overlay already exists
        val existingOverlay = decorView.findViewWithTag<android.view.View>(CAPTURE_OVERLAY_TAG)
        if (existingOverlay != null) {
            existingOverlay.isClickable = blocksInput
            existingOverlay.isFocusable = blocksInput
            return existingOverlay
        }

        val overlay = FrameLayout(activity).apply {
            tag = CAPTURE_OVERLAY_TAG
            setBackgroundColor(0xD9000000.toInt()) // 85% black
            isClickable = blocksInput
            isFocusable = blocksInput

            val warningText = TextView(activity).apply {
                text = SEAStrings.captureWarning(activity)
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 16f
                gravity = Gravity.CENTER
                setPadding(48, 48, 48, 48)
            }
            addView(warningText, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))
        }

        val layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        decorView.addView(overlay, layoutParams)

        return overlay
    }

    /**
     * Remove the capture overlay from the given window.
     */
    fun removeCaptureOverlay(activity: Activity) {
        val window = activity.window ?: return
        val decorView = window.decorView as? FrameLayout ?: return
        val overlay = decorView.findViewWithTag<android.view.View>(CAPTURE_OVERLAY_TAG)
        overlay?.let { decorView.removeView(it) }
    }

    private const val CAPTURE_OVERLAY_TAG = "sea_capture_overlay"
}

/**
 * The result of evaluating screen capture state against the configured policy.
 */
internal sealed class SEACaptureAction {
    object None : SEACaptureAction()
    data class Overlay(val blocksInput: Boolean) : SEACaptureAction()
}

/**
 * Interface for screen capture callbacks (API 30+).
 * This is a SAM interface to avoid requiring the platform-specific
 * ScreenCaptureCallback class in the type signature.
 */
fun interface ScreenCaptureCallback {
    fun onScreenCaptureChanged(captured: Boolean)
}
