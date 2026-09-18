package com.bankerise.sea.demo.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bankerise.sea.core.SEAEnvironment
import com.bankerise.sea.demo.model.AppSettings
import com.bankerise.sea.demo.networking.FuzzCorpus

@Composable
fun FuzzScreen(appSettings: AppSettings) {
    val env = SEAEnvironment.current
    val results = remember(appSettings.allowedDomains) {
        FuzzCorpus.run(env, appSettings.allowedDomainsArray)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            text = "§23.2 Navigation Fuzz Corpus",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(16.dp)
        )

        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(results) { result ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = if (result.allowed)
                            Color(0xFFE8F5E9)  // light green
                        else
                            Color(0xFFFFEBEE)  // light red
                    )
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text(
                            text = result.entry.label,
                            style = MaterialTheme.typography.labelLarge
                        )
                        Text(
                            text = result.entry.url,
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 10.sp
                            ),
                            maxLines = 2
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = if (result.allowed) "ALLOWED" else "BLOCKED",
                            style = MaterialTheme.typography.labelMedium,
                            color = if (result.allowed) Color(0xFF2E7D32) else Color(0xFFC62828)
                        )
                        if (result.reason != null) {
                            Text(
                                text = "Reason: ${result.reason}",
                                style = MaterialTheme.typography.bodySmall,
                                color = Color(0xFF666666)
                            )
                        }
                    }
                }
            }
        }
    }
}
