package com.bankerise.sea.demo

import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import com.bankerise.sea.core.SEASession
import com.bankerise.sea.demo.model.AppSettings
import com.bankerise.sea.demo.model.SessionResultStore
import com.bankerise.sea.demo.model.TelemetryStore
import com.bankerise.sea.demo.networking.GatewayClient
import com.bankerise.sea.demo.networking.MockGateway
import com.bankerise.sea.demo.ui.RootNavigation
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val scope = MainScope()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val appSettings = AppSettings.getInstance(this)

        setContent {
            MaterialTheme {
                RootNavigation(
                    appSettings = appSettings,
                    sessionResult = SessionResultStore.shared,
                    telemetryStore = TelemetryStore.shared,
                    onStartLogin = { mockUrl ->
                        startLogin(appSettings, mockUrl)
                    }
                )
            }
        }
    }

    private fun startLogin(appSettings: AppSettings, mockUrl: String) {
        val url = if (appSettings.useMockGateway) {
            Uri.parse(mockUrl)
        } else {
            // For the real gateway, we need to run the two-hop sequence.
            // This is a simplified path — the demo app would normally do
            // this in a coroutine with proper error handling.
            Uri.parse(mockUrl)  // placeholder
        }

        val config = appSettings.toSEAConfig(url)

        SEASession.start(
            activity = this,
            config = config,
            callbacks = SEASession.Callbacks(
                onCaptured = { params ->
                    SessionResultStore.shared.onCaptured(params)
                },
                onCancelled = {
                    SessionResultStore.shared.onCancelled()
                },
                onError = { error ->
                    SessionResultStore.shared.onError(error)
                }
            )
        )
    }
}
