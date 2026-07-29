package com.demo_rn

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableMap
import java.util.Properties

/**
 * Reads `bankerise-sea.properties` from the app's assets and exposes
 * the values to JS as a NativeModule. The demo harness uses these as
 * editable defaults for SEAConfig fields.
 *
 * Properties file lives at `android/bankerise-sea.properties` and is
 * copied into assets via the `copyProperties` task in build.gradle.
 */
class SEAConfigProvider(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "SEAConfigProvider"

    private val props: Properties by lazy {
        val p = Properties()
        try {
            reactApplicationContext.assets.open("bankerise-sea.properties").use {
                p.load(it)
            }
        } catch (_: Exception) {
            // File missing — defaults below apply.
        }
        p
    }

    /**
     * Returns all config values as a WritableMap so JS can read them
     * in a single synchronous call at startup.
     */
    @ReactMethod(isBlockingSynchronousMethod = true)
    fun getConfig(): WritableMap {
        return Arguments.createMap().apply {
            putString("callbackScheme", props.getProperty("callbackScheme", "bankerise-auth"))
            putString("authDomains", props.getProperty("authDomains", "auth.bank.local,localhost,showcase-client-gw.demo.proxym-it.net,platform-keycloak.pres.proxym-it.net"))
            putString("allowedPorts", props.getProperty("allowedPorts", "-1,443"))
            putInt("maxUrlLengthBytes", props.getProperty("maxUrlLengthBytes", "2048").toIntOrNull() ?: 2048)
        }
    }
}
