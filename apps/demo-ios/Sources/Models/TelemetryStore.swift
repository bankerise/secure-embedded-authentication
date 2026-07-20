import Foundation
import SEACore

/// One row in the on-screen telemetry console. SEAEvent itself isn't Identifiable,
/// so we wrap it for SwiftUI's List.
struct TelemetryLogEntry: Identifiable {
    let id = UUID()
    let name: String
    let properties: [String: String]
    let timestamp: Date

    init(event: SEAEvent) {
        self.name = event.name
        self.properties = event.properties
        self.timestamp = event.timestamp
    }

    var propertiesText: String {
        properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    var formattedTimestamp: String {
        Self.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// Implements SEATelemetrySink (api-contract-ios-v1.md §3.6) and buffers every
/// event SEACore emits so the tester can verify §20 events fire live, on device.
/// This is how §23.2's "must be blocked and telemetered" requirement is checked
/// visually for the navigation fuzz corpus, and how AUTH_* lifecycle events are
/// verified for real login attempts.
final class TelemetryStore: ObservableObject, SEATelemetrySink {
    static let shared = TelemetryStore()

    @Published private(set) var entries: [TelemetryLogEntry] = []

    private init() {}

    // SEATelemetrySink — contract guarantees this is called on the main thread.
    func record(_ event: SEAEvent) {
        entries.append(TelemetryLogEntry(event: event))
    }

    func clear() {
        entries.removeAll()
    }

    /// Text blob for the "copy all" action.
    var copyableText: String {
        entries
            .map { "[\($0.formattedTimestamp)] \($0.name) — \($0.propertiesText)" }
            .joined(separator: "\n")
    }
}
