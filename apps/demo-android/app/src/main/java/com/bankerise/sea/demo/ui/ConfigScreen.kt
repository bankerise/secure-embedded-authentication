package com.bankerise.sea.demo.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bankerise.sea.demo.model.AppSettings

@Composable
fun ConfigScreen(
    appSettings: AppSettings,
    onStartLogin: (String) -> Unit
) {
    var gatewayBaseUrl by remember { mutableStateOf(appSettings.gatewayBaseUrl) }
    var callbackScheme by remember { mutableStateOf(appSettings.callbackScheme) }
    var allowedDomains by remember { mutableStateOf(appSettings.allowedDomains) }
    var presentation by remember { mutableStateOf(appSettings.presentation) }
    var useMockGateway by remember { mutableStateOf(appSettings.useMockGateway) }
    var mockRedirectUrl by remember { mutableStateOf(appSettings.mockRedirectUrl) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Gateway Configuration", style = MaterialTheme.typography.titleMedium)

        OutlinedTextField(
            value = gatewayBaseUrl,
            onValueChange = { gatewayBaseUrl = it },
            label = { Text("Gateway base URL") },
            modifier = Modifier.fillMaxWidth(),
            enabled = !useMockGateway
        )

        OutlinedTextField(
            value = callbackScheme,
            onValueChange = { callbackScheme = it },
            label = { Text("Callback scheme") },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = allowedDomains,
            onValueChange = { allowedDomains = it },
            label = { Text("Allowed domains (comma-separated)") },
            modifier = Modifier.fillMaxWidth()
        )

        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(
                checked = presentation == "FULLSCREEN",
                onCheckedChange = {
                    presentation = if (it) "FULLSCREEN" else "SHEET"
                }
            )
            Spacer(Modifier.width(8.dp))
            Text("Fullscreen presentation")
        }

        HorizontalDivider()

        Text("Mock Gateway", style = MaterialTheme.typography.titleMedium)

        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(
                checked = useMockGateway,
                onCheckedChange = { useMockGateway = it }
            )
            Spacer(Modifier.width(8.dp))
            Text("Use mock gateway")
        }

        OutlinedTextField(
            value = mockRedirectUrl,
            onValueChange = { mockRedirectUrl = it },
            label = { Text("Mock redirect URL") },
            modifier = Modifier.fillMaxWidth(),
            enabled = useMockGateway
        )

        Spacer(Modifier.height(8.dp))

        Button(
            onClick = {
                // Persist all settings
                appSettings.gatewayBaseUrl = gatewayBaseUrl
                appSettings.callbackScheme = callbackScheme
                appSettings.allowedDomains = allowedDomains
                appSettings.presentation = presentation
                appSettings.useMockGateway = useMockGateway
                appSettings.mockRedirectUrl = mockRedirectUrl

                val url = if (useMockGateway) mockRedirectUrl else ""
                onStartLogin(url)
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Start login")
        }
    }
}
