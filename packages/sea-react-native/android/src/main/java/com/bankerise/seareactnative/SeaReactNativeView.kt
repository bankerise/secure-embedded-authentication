package com.bankerise.seareactnative

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.View
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.uimanager.UIManagerHelper

/**
 * The native Android view for the React Native Fabric component.
 * Holds prop values and triggers the auth session when both props
 * and a window are available.
 *
 * Mirrors `ios/SeaReactNativeView.mm` exactly:
 * - `startIfNeeded` fires once both `authorizeUrl` and an Activity are
 *   available (§7.2 lifecycle).
 * - At most one terminal event fires (`onCaptured`/`onCancelled`/`onError`).
 * - Event dispatch goes through [eventEmitter] (set by the ViewManager),
 *   keeping this class free of Fabric/Old-Arch specifics.
 */
class SeaReactNativeView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    /** Set by [SeaReactNativeViewManager.createViewInstance]. */
    internal var reactContext: ReactContext? = null

    /**
     * Event dispatch callback. Set by [SeaReactNativeViewManager] to route
     * Fabric events through [UIManagerHelper]. Keeps this View decoupled
     * from the event-dispatch mechanism.
     */
    internal var eventEmitter: ((String, WritableMap?) -> Unit)? = null

    // ── Props (set by ViewManager @ReactProp methods) ──

    var authorizeUrl: String = ""
    var presentation: String = "sheet"
    var headerBackground: Int? = null
    var headerText: Int? = null
    var accent: Int? = null
    var closeIconTint: Int? = null
    var cornerRadius: Float? = null
    var title: String = ""
    var allowedDomains: List<String> = emptyList()
    var timeoutMs: Int = 0
    var callbackScheme: String = ""
    var allowedPorts: Set<Int> = emptySet()
    var maxUrlLengthBytes: Int = 2048

    // ── Terminal-event callbacks (set by ViewManager) ──

    var onCaptured: ((String) -> Unit)? = null
    var onCancelled: (() -> Unit)? = null
    var onError: ((String, String?) -> Unit)? = null

    // ── Internal lifecycle state ──

    private var hasStarted = false
    private var hasFinished = false
    private var startedUrl: String = ""

    /**
     * Called from [SeaReactNativeViewManager.onAfterUpdateTransaction] and
     * [onAttachedToWindow]. Starts a session when a non-empty `authorizeUrl`
     * that differs from the last-started URL is available — mirrors the iOS
     * `startIfNeeded` dual-hook pattern. Clearing `authorizeUrl` resets the
     * one-shot guards so a later re-login can start a fresh session even if
     * this View instance is reused (Fabric view recycling) rather than
     * recreated from scratch.
     */
    fun startIfNeeded() {
        if (authorizeUrl.isEmpty()) {
            reset()
            return
        }
        if (startedUrl == authorizeUrl) return

        val activity = reactContext?.currentActivity ?: return
        hasStarted = true
        hasFinished = false
        startedUrl = authorizeUrl

        val block = Runnable {
            SEABridgePresenter.start(
                activity = activity,
                authorizeUrl = authorizeUrl,
                presentation = presentation,
                allowedDomains = allowedDomains,
                timeoutMs = timeoutMs,
                callbackScheme = callbackScheme,
                allowedPorts = allowedPorts,
                maxUrlLengthBytes = maxUrlLengthBytes,
                headerBackground = headerBackground,
                headerText = headerText,
                accent = accent,
                closeIconTint = closeIconTint,
                cornerRadius = cornerRadius,
                title = title,
                callbacks = SEABridgePresenter.BridgeCallbacks(
                    onCaptured = { paramsJson ->
                        val map = Arguments.createMap().apply {
                            putString("paramsJson", paramsJson)
                        }
                        emitTerminal("onCaptured", map)
                    },
                    onCancelled = { emitTerminal("onCancelled", null) },
                    onError = { code, message ->
                        val data = WritableNativeMap().apply {
                            putString("code", code)
                            if (message != null) putString("message", message)
                        }
                        emitTerminal("onError", data)
                    }
                )
            )
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            block.run()
        } else {
            Handler(Looper.getMainLooper()).post(block)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startIfNeeded()
    }

    fun reset() {
        hasStarted = false
        hasFinished = false
        startedUrl = ""
    }

    // ── Event dispatch (mirrors iOS emitCaptured/emitCancelled/emitError) ──

    /**
     * Dispatches at most one terminal event, then marks the view as
     * finished. Subsequent calls are suppressed (§7.2 exactly-once
     * terminal callback).
     */
    private fun emitTerminal(eventName: String, data: WritableMap?) {
        if (hasFinished) return
        hasFinished = true
        eventEmitter?.invoke(eventName, data)
    }
}
