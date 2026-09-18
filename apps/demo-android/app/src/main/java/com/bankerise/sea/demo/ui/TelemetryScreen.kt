package com.bankerise.sea.demo.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bankerise.sea.demo.model.TelemetryStore

@Composable
fun TelemetryScreen(telemetryStore: TelemetryStore) {
    val context = LocalContext.current
    var events by remember { mutableStateOf(telemetryStore.events) }

    DisposableEffect(telemetryStore) {
        val listener = { events = telemetryStore.events; Unit }
        telemetryStore.addListener(listener)
        onDispose { telemetryStore.removeListener(listener) }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = {
                    val text = telemetryStore.allEventsAsText()
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("telemetry", text))
                    Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                }
            ) {
                Text("Copy all")
            }
            OutlinedButton(onClick = { telemetryStore.clear() }) {
                Text("Clear")
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(events.reversed()) { event ->
                val props = event.properties.entries.joinToString(", ") { "${it.key}=${it.value}" }
                Text(
                    text = "${event.name} {$props}",
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp
                    )
                )
            }
        }
    }
}
