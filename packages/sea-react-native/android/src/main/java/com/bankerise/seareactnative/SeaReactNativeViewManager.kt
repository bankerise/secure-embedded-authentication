package com.bankerise.seareactnative

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.uimanager.ReactStylesDiffMap
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.events.Event
import android.util.Log

/**
 * Fabric-compatible ViewManager for `SeaReactNativeView`.
 *
 * Mirrors `ios/SeaReactNativeView.mm`: reads every prop, converts
 * them to primitives, hands them to [SEABridgePresenter] (via the
 * [SeaReactNativeView]), and converts results back to Fabric events.
 * No authentication/navigation/validation logic lives here.
 *
 * Registered in [SeaReactNativePackage].
 */
class SeaReactNativeViewManager : SimpleViewManager<SeaReactNativeView>() {

    private val TAG = "SeaReactNativeViewManager"

    override fun getName(): String = "SeaReactNativeView"

    override fun createViewInstance(context: ThemedReactContext): SeaReactNativeView {
        return SeaReactNativeView(context).apply {
            reactContext = context
            eventEmitter = { eventName, data -> emitFabricEvent(this, eventName, data) }
        }
    }

    /**
     * §7.2 lifecycle: props arrive via @ReactProp, then this fires.
     * The view's `startIfNeeded` only acts once both a real
     * `authorizeUrl` and an Activity are available.
     */
    override fun onAfterUpdateTransaction(view: SeaReactNativeView) {
        super.onAfterUpdateTransaction(view)
        Log.d(TAG, "onAfterUpdateTransaction authorizeUrl=${view.authorizeUrl} presentation=${view.presentation}")
        view.startIfNeeded()
    }

    override fun updateProperties(viewToUpdate: SeaReactNativeView, props: ReactStylesDiffMap) {
        Log.d(TAG, "updateProperties keys=${props.toMap().keys}")
        super.updateProperties(viewToUpdate, props)
    }

    /** §7.2: if view is torn down before a terminal callback, reset state. */
    override fun onDropViewInstance(view: SeaReactNativeView) {
        view.reset()
        super.onDropViewInstance(view)
    }

    // ── Props (mirrors codegen spec NativeProps) ──

    @ReactProp(name = "authorizeUrl")
    fun setAuthorizeUrl(view: SeaReactNativeView, url: String?) {
        view.authorizeUrl = url ?: ""
    }

    @ReactProp(name = "presentation")
    fun setPresentation(view: SeaReactNativeView, presentation: String?) {
        view.presentation = presentation ?: "sheet"
    }

    @ReactProp(name = "appearance")
    fun setAppearance(view: SeaReactNativeView, appearance: ReadableMap?) {
        if (appearance == null) return
        if (appearance.hasKey("headerBackground") && !appearance.isNull("headerBackground")) {
            view.headerBackground = appearance.getInt("headerBackground")
        }
        if (appearance.hasKey("headerText") && !appearance.isNull("headerText")) {
            view.headerText = appearance.getInt("headerText")
        }
        if (appearance.hasKey("accent") && !appearance.isNull("accent")) {
            view.accent = appearance.getInt("accent")
        }
        if (appearance.hasKey("closeIconTint") && !appearance.isNull("closeIconTint")) {
            view.closeIconTint = appearance.getInt("closeIconTint")
        }
        if (appearance.hasKey("cornerRadius") && !appearance.isNull("cornerRadius")) {
            view.cornerRadius = appearance.getDouble("cornerRadius").toFloat()
        }
        if (appearance.hasKey("title") && !appearance.isNull("title")) {
            view.title = appearance.getString("title") ?: ""
        }
    }

    // ── Fabric event dispatch ──

    /**
     * Dispatches a Fabric event through [UIManagerHelper]. Works on both
     * old and new architecture.
     */
    private fun emitFabricEvent(view: SeaReactNativeView, eventName: String, data: WritableMap?) {
        val reactContext = view.reactContext ?: return
        val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
        UIManagerHelper.getEventDispatcherForReactTag(reactContext, view.id)
            ?.dispatchEvent(SeaReactNativeViewEvent(surfaceId, view.id, eventName, data))
    }

    /**
     * Fabric event wrapper. `canCoalesce = false` ensures every terminal
     * event (onCaptured / onCancelled / onError) is delivered exactly
     * once (§7.2).
     */
    private class SeaReactNativeViewEvent(
        surfaceId: Int,
        viewTag: Int,
        private val _eventName: String,
        private val eventData: WritableMap?
    ) : Event<SeaReactNativeViewEvent>(surfaceId, viewTag) {
        override fun getEventName(): String = _eventName
        override fun canCoalesce(): Boolean = false
        override fun getCoalescingKey(): Short = 0
        override fun getEventData(): WritableMap? = eventData
    }
}
