package com.bankerise.sea.demo

import android.app.Application
import com.bankerise.sea.core.SEASession
import com.bankerise.sea.demo.model.TelemetryStore

class SEADemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Wire the telemetry sink before any session can start (§20.1),
        // so no early events are dropped.
        SEASession.telemetrySink = TelemetryStore.shared
    }
}
