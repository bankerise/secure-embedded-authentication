import SwiftUI
import SEACore

@main
struct SEADemoApp: App {
    init() {
        // §20.1: wire the telemetry sink before any session can start, so no
        // early events are dropped. TelemetryStore.shared is a strong
        // singleton reference keeping this weak var alive for the app's
        // lifetime.
        SEASession.telemetrySink = TelemetryStore.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
