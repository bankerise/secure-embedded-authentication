import SwiftUI

/// Root of the app. Config is the first/default tab per the task brief ("a
/// config screen (the app's root)"); Results, Telemetry, and the Fuzz screen
/// are siblings so the tester can flip between "start a session" and "inspect
/// what happened" without losing state (all backed by shared singletons).
struct RootTabView: View {
    @StateObject private var runner = LoginRunner()

    var body: some View {
        TabView {
            ConfigView(settings: AppSettings.shared, runner: runner)
                .tabItem { Label("Config", systemImage: "gearshape") }

            ResultsView(store: SessionResultStore.shared)
                .tabItem { Label("Result", systemImage: "checkmark.circle") }

            TelemetryConsoleView(store: TelemetryStore.shared)
                .tabItem { Label("Telemetry", systemImage: "waveform.path.ecg") }

            FuzzView(settings: AppSettings.shared)
                .tabItem { Label("Fuzz", systemImage: "ladybug") }
        }
    }
}
