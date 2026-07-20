import SwiftUI
import UIKit

/// Live console for every SEAEvent SEACore emits (§20). This is how the tester
/// verifies, on-device, that lifecycle events (AUTH_WEBVIEW_OPENED, AUTH_NAV_BLOCKED,
/// AUTH_CAPTURE_DETECTED, ...) actually fire — including for the navigation
/// fuzz corpus.
struct TelemetryConsoleView: View {
    @ObservedObject var store: TelemetryStore
    @State private var didCopy = false

    var body: some View {
        NavigationView {
            Group {
                if store.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No telemetry events yet.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(store.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.name)
                                    .font(.system(.body, design: .monospaced).bold())
                                Spacer()
                                Text(entry.formattedTimestamp)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !entry.properties.isEmpty {
                                Text(entry.propertiesText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Telemetry (\(store.entries.count))")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { store.clear() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(didCopy ? "Copied" : "Copy all") {
                        UIPasteboard.general.string = store.copyableText
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            didCopy = false
                        }
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
