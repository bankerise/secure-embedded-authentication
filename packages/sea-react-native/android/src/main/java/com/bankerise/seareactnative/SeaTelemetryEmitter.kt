package com.bankerise.seareactnative

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.bankerise.sea.core.SEAEvent
import com.bankerise.sea.core.SEASession
import com.bankerise.sea.core.SEATelemetrySink
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.modules.core.RCTNativeAppEventEmitter

/**
 * Bridges `sea-core-android`'s §20 telemetry sink and two demo-harness
 * utilities (purge web data, clipboard copy) to JS. This is presentation-
 * adjacent debug tooling, not part of the §7.1 SecureAuthenticationView
 * contract — kept in its own native module rather than the Fabric view.
 *
 * Mirrors `ios/SeaTelemetryEmitter.swift` exactly.
 */
class SeaTelemetryEmitter(
    reactContext: ReactApplicationContext
) : ReactContextBaseJavaModule(reactContext), SEATelemetrySink {

    private var hasListeners = false

    override fun getName(): String = "SeaTelemetryEmitter"

    // ── Lifecycle (called by RN NativeEventEmitter) ──

    @ReactMethod
    fun addListener(eventName: String) {
        // Required for RN event emitter — keeps subscription count.
        hasListeners = true
        SEASession.telemetrySink = this
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        hasListeners = false
        SEASession.telemetrySink = null
    }

    // ── SEATelemetrySink (§20) ──

    /**
     * Contract guarantees this is called on the main thread.
     * Forwards every [SEAEvent] to JS subscribers as a
     * `SeaTelemetryEvent`.
     */
    override fun record(event: SEAEvent) {
        if (!hasListeners) return
        val params = Arguments.createMap().apply {
            putString("name", event.name)
            putMap("properties", Arguments.createMap().apply {
                event.properties.forEach { (k, v) -> putString(k, v) }
            })
            putDouble("timestampMs", event.timestamp.toDouble())
        }
        reactApplicationContext
            .getJSModule(RCTNativeAppEventEmitter::class.java)
            .emit("SeaTelemetryEvent", params)
    }

    // ── Demo-harness utilities ──

    /** Copies text to the system clipboard (demo-harness convenience only). */
    @ReactMethod
    fun copyToClipboard(text: String) {
        val clipboard = reactApplicationContext
            .getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("SEA", text))
    }

    /** §11.3 step 2 — purges the shared WebView data store. */
    @ReactMethod
    fun purgeWebData(promise: Promise) {
        SEASession.purgeWebData(reactApplicationContext) {
            promise.resolve(null)
        }
    }
}
