package com.bankerise.seareactnative

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/**
 * React Native autolinking entry point. Registers the Fabric view
 * manager and the telemetry native module.
 *
 * Mirrors the iOS registration: `SeaReactNativeView` (Fabric component)
 * + `SeaTelemetryEmitter` (NativeModule).
 */
class SeaReactNativePackage : ReactPackage {

    override fun createNativeModules(
        reactContext: ReactApplicationContext
    ): List<NativeModule> {
        return listOf(SeaTelemetryEmitter(reactContext))
    }

    override fun createViewManagers(
        reactContext: ReactApplicationContext
    ): List<ViewManager<*, *>> {
        return listOf(SeaReactNativeViewManager())
    }
}
