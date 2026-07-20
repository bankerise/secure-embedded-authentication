import SwiftUI
import SEACore

/// Shows the last SEASession terminal outcome verbatim.
///
/// On `onCaptured`, ALL raw callback params are rendered in a table — including
/// `code` / `state` / `session_state`. This is a dev harness, not a production
/// integration: showing them here is intentional and correct (SEACore itself
/// does no semantic validation of these per §6.3 / contract §3.4).
struct ResultsView: View {
    @ObservedObject var store: SessionResultStore

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Result")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") { store.reset() }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        switch store.outcome {
        case .none:
            emptyState

        case .captured(let raw, let at):
            List {
                Section("onCaptured — \(Self.timeFormatter.string(from: at))") {
                    if raw.isEmpty {
                        Text("(no params)").foregroundColor(.secondary)
                    } else {
                        ForEach(raw.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                            HStack(alignment: .top) {
                                Text(pair.key)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Text(pair.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

        case .cancelled(let at):
            outcomeBanner(
                title: "onCancelled",
                detail: "User dismissed the session.",
                at: at,
                color: .orange
            )

        case .error(let error, let at):
            outcomeBanner(
                title: "onError",
                detail: error.demoDescription,
                at: at,
                color: .red
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No session has completed yet.")
                .foregroundColor(.secondary)
            Text("Run \"Start login\" from the Config tab.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func outcomeBanner(title: String, detail: String, at: Date, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(detail)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text(Self.timeFormatter.string(from: at))
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
