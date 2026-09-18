package com.bankerise.sea.demo.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.bankerise.sea.demo.model.AppSettings
import com.bankerise.sea.demo.model.SessionResultStore
import com.bankerise.sea.demo.model.TelemetryStore

sealed class Screen(val route: String, val label: String) {
    data object Config : Screen("config", "Config")
    data object Result : Screen("result", "Result")
    data object Telemetry : Screen("telemetry", "Telemetry")
    data object Fuzz : Screen("fuzz", "Fuzz")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RootNavigation(
    appSettings: AppSettings,
    sessionResult: SessionResultStore,
    telemetryStore: TelemetryStore,
    onStartLogin: (String) -> Unit
) {
    val navController = rememberNavController()
    val screens = listOf(Screen.Config, Screen.Result, Screen.Telemetry, Screen.Fuzz)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SEA Demo") }
            )
        },
        bottomBar = {
            NavigationBar {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination
                screens.forEach { screen ->
                    NavigationBarItem(
                        icon = {
                            Icon(
                                when (screen) {
                                    Screen.Config -> Icons.Default.Check
                                    Screen.Result -> Icons.Default.List
                                    Screen.Telemetry -> Icons.Default.Refresh
                                    Screen.Fuzz -> Icons.Default.Warning
                                },
                                contentDescription = screen.label
                            )
                        },
                        label = { Text(screen.label) },
                        selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Config.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Config.route) {
                ConfigScreen(
                    appSettings = appSettings,
                    onStartLogin = onStartLogin
                )
            }
            composable(Screen.Result.route) {
                ResultScreen(sessionResult = sessionResult)
            }
            composable(Screen.Telemetry.route) {
                TelemetryScreen(telemetryStore = telemetryStore)
            }
            composable(Screen.Fuzz.route) {
                FuzzScreen(appSettings = appSettings)
            }
        }
    }
}
