package com.bankerise.seareactnative

import android.app.Activity
import android.net.Uri
import android.util.Log
import com.bankerise.sea.core.SEAConfig
import com.bankerise.sea.core.SEAAppearance
import com.bankerise.sea.core.SEAAuthMode
import com.bankerise.sea.core.SEAError
import com.bankerise.sea.core.SEAPresentation
import com.bankerise.sea.core.SEAPropertiesLoader
import com.bankerise.sea.core.SEASession
import org.json.JSONObject

/**
 * The entire bridge-side "logic": marshal primitive prop values into a
 * [SEAConfig], call [SEASession.start], and marshal the result back to
 * primitives. No authentication/navigation/validation logic lives here —
 * all of that is `sea-core-android` (spec §4.2, §7).
 *
 * Only file in this module that imports `com.bankerise.sea.core.*`.
 * Mirrors `ios/SEABridgePresenter.swift` exactly.
 */
object SEABridgePresenter {

    /**
     * Marshals the per-session/UI prop values into [SEAConfig] and
     * [SEAAppearance], calls [SEASession.start], and returns `true` if
     * the auth surface was launched. On validation failure,
     * [callbacks.onError] fires before this returns `false`.
     *
     * Security knobs (callback scheme, allowed domains, allowed ports,
     * max URL length, timeout) are NOT props — they are owned by the
     * platform config: `bankerise-sea.properties` loaded via
     * [SEAPropertiesLoader]. Only `authorizeUrl`, `presentation`,
     * `authMode` and `appearance` cross the bridge. Mirrors
     * `ios/SEABridgePresenter.swift`.
     */
    fun start(
        activity: Activity,
        authorizeUrl: String,
        presentation: String,
        authMode: String,
        headerBackground: Int?,
        headerText: Int?,
        accent: Int?,
        closeIconTint: Int?,
        cornerRadius: Float?,
        title: String,
        callbacks: BridgeCallbacks
    ): Boolean {
        val url = try {
            Uri.parse(authorizeUrl)
        } catch (_: Exception) {
            callbacks.onError("invalid_authorize_url", "malformed authorizeUrl")
            return false
        }

        var appearance = SEAAppearance.default
        if (headerBackground != null) appearance = appearance.copy(headerBackground = headerBackground)
        if (headerText != null) appearance = appearance.copy(headerText = headerText)
        if (accent != null) appearance = appearance.copy(accent = accent)
        if (closeIconTint != null) appearance = appearance.copy(closeIconTint = closeIconTint)
        if (cornerRadius != null && cornerRadius > 0f) appearance = appearance.copy(cornerRadius = cornerRadius)
        if (title.isNotEmpty()) appearance = appearance.copy(title = title)

        // Source of truth for all security knobs (§4.5, §7.1/§7.3): the
        // host app's bankerise-sea.properties. Only the per-session/UI
        // values are overridden here.
        val config = SEAPropertiesLoader.loadConfig(activity).copy(
            authorizeUrl = url,
            presentation = if (presentation == "fullscreen") {
                SEAPresentation.FULLSCREEN
            } else {
                SEAPresentation.SHEET
            },
            appearance = appearance,
            authMode = if (authMode == "nativeBrowser") {
                SEAAuthMode.NATIVE_BROWSER
            } else {
                SEAAuthMode.EMBEDDED
            }
        )

        val seaCallbacks = SEASession.Callbacks(
            onCaptured = { params ->
                val json = jsonString(params.raw)
                Log.d("SEABridgePresenter", "onCaptured: raw=${params.raw} json=$json")
                callbacks.onCaptured(json)
            },
            onCancelled = {
                Log.d("SEABridgePresenter", "onCancelled")
                callbacks.onCancelled()
            },
            onError = { error ->
                val (code, message) = taxonomy(error)
                Log.d("SEABridgePresenter", "onError: code=$code message=$message")
                callbacks.onError(code, message)
            }
        )

        return SEASession.start(activity, config, seaCallbacks)
    }

    /** JSON-serialize a `Map<String, String>` via `org.json.JSONObject`. */
    private fun jsonString(raw: Map<String, String>): String {
        return try {
            val obj = JSONObject()
            raw.forEach { (k, v) -> obj.put(k, v) }
            obj.toString()
        } catch (_: Exception) {
            "{}"
        }
    }

    /**
     * Maps every [SEAError] case to the bridge's wire taxonomy verbatim
     * (spec §7.2): network, timeout, cancelled, invalid_authorize_url,
     * server_error, webauthn_unavailable, kill_switched.
     */
    private fun taxonomy(error: SEAError): Pair<String, String?> = when (error) {
        is SEAError.Network -> "network" to error.underlying
        is SEAError.Timeout -> "timeout" to null
        is SEAError.Cancelled -> "cancelled" to null
        is SEAError.InvalidAuthorizeUrl -> "invalid_authorize_url" to error.reason.name
        is SEAError.ServerError -> "server_error" to error.statusCode.toString()
        is SEAError.WebauthnUnavailable -> "webauthn_unavailable" to null
        is SEAError.KillSwitched -> "kill_switched" to null
    }

    /**
     * Callbacks carrying only primitive/bridgeable types — `sea-core-android`'s
     * own types ([SEACallbackParams][com.bankerise.sea.core.SEACallbackParams],
     * [SEAError]) never cross into the View layer.
     *
     * Mirrors `ios/SEABridgePresenter.swift` `SEABridgeCallbacks`.
     */
    class BridgeCallbacks(
        val onCaptured: (String) -> Unit,
        val onCancelled: () -> Unit,
        val onError: (String, String?) -> Unit
    )
}
