package com.bankerise.sea.core

import android.app.Activity
import androidx.annotation.RequiresApi

/**
 * Isolated helper for screen-capture monitoring on API 34+.
 *
 * This class is intentionally separate from [SEAScreenSecurity] so that
 * the reference to [Activity.ScreenCaptureCallback] is only resolved when
 * this class is loaded — which only happens inside a `Build.VERSION.SDK_INT >= 34`
 * guard.  If this reference lived directly in [SEAScreenSecurity], the ART
 * class verifier would resolve it when [SEAScreenSecurity] is first loaded
 * (e.g. via [SEAScreenSecurity.applySecureFlag]), crashing on API < 34.
 */
@RequiresApi(34)
internal class CaptureMonitorHelper(
    private val activity: Activity,
    private val onCaptured: (Boolean) -> Unit
) {
    private val callback = Activity.ScreenCaptureCallback {
        onCaptured(true)
    }

    private var registered = false

    init {
        try {
            activity.registerScreenCaptureCallback(activity.mainExecutor, callback)
            registered = true
        } catch (_: SecurityException) {
            // API 36+ requires DETECT_SCREEN_CAPTURE; older APIs don't
            // enforce it. Silently degrade to FLAG_SECURE-only protection.
        }
    }

    fun unregister(activity: Activity) {
        if (registered) {
            activity.unregisterScreenCaptureCallback(callback)
            registered = false
        }
    }
}
