package com.bankerise.sea.demo.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bankerise.sea.core.SEAError
import com.bankerise.sea.demo.model.SessionResultStore

@Composable
fun ResultScreen(sessionResult: SessionResultStore) {
    var result by remember { mutableStateOf(sessionResult.lastResult) }

    DisposableEffect(sessionResult) {
        val listener = { result = sessionResult.lastResult; Unit }
        sessionResult.addListener(listener)
        onDispose { sessionResult.removeListener(listener) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Session Result", style = MaterialTheme.typography.titleMedium)

        when (val r = result) {
            null -> {
                Text(
                    "No session completed yet. Tap 'Start login' on the Config tab.",
                    style = MaterialTheme.typography.bodyMedium
                )
            }

            is SessionResultStore.Result.Captured -> {
                Text("onCaptured", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(4.dp))
                r.params.raw.forEach { (key, value) ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            key,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.width(120.dp)
                        )
                        Text(
                            value,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }

            is SessionResultStore.Result.Cancelled -> {
                Text("onCancelled", style = MaterialTheme.typography.labelLarge)
                Text("The user cancelled the login session.")
            }

            is SessionResultStore.Result.Failed -> {
                Text("onError", style = MaterialTheme.typography.labelLarge)
                Text("Error type: ${r.error::class.simpleName}")
                when (r.error) {
                    is SEAError.Network -> Text("Detail: ${(r.error as SEAError.Network).underlying}")
                    is SEAError.ServerError -> Text("Status code: ${(r.error as SEAError.ServerError).statusCode}")
                    is SEAError.InvalidAuthorizeUrl -> Text("Reason: ${(r.error as SEAError.InvalidAuthorizeUrl).reason}")
                    else -> Text("Detail: ${r.error}")
                }
            }
        }
    }
}
