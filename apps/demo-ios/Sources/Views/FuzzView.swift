import SwiftUI
import SEACore

private enum FuzzOutcome {
    case notRun
    case allowed
    case blocked(SEAInvalidURLReason)
    case malformedURL
}

private struct FuzzRunResult: Identifiable {
    let id: UUID
    let entry: FuzzCorpusEntry
    let outcome: FuzzOutcome
}

/// One-tap §23.2 navigation-fuzzing check: runs the hardcoded hostile-URL
/// corpus through SEACore's own `SEAAuthorizeURLValidator` and shows allow/block
/// per entry. This screen contains NO validation logic of its own — every
/// verdict below comes from the core. See FuzzCorpus.swift for the important
/// caveat about which of the core's two policy surfaces this actually exercises.
struct FuzzView: View {
    @ObservedObject var settings: AppSettings
    @State private var results: [FuzzRunResult] = FuzzCorpus.entries.map {
        FuzzRunResult(id: $0.id, entry: $0, outcome: .notRun)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button("Run fuzz corpus") { runCorpus() }
                } footer: {
                    Text(
                        "Runs each URL below through SEAAuthorizeURLValidator.validate " +
                        "against SEAEnvironment.current, narrowed by the Config screen's " +
                        "allowed-domains list (\(settings.allowedDomainsArray.joined(separator: ",")))."
                    )
                }

                Section("Corpus") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                verdictIcon(result.outcome)
                                Text(result.entry.label)
                                    .font(.subheadline.bold())
                            }
                            Text(result.entry.urlString.prefix(120) + (result.entry.urlString.count > 120 ? "…" : ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            Text(verdictText(result.outcome))
                                .font(.caption.monospaced())
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Navigation Fuzz")
        }
        .navigationViewStyle(.stack)
    }

    private func runCorpus() {
        let allowlist = settings.allowedDomainsArray
        results = FuzzCorpus.entries.map { entry in
            guard let url = URL(string: entry.urlString) else {
                return FuzzRunResult(id: entry.id, entry: entry, outcome: .malformedURL)
            }
            let verdict = SEAAuthorizeURLValidator.validate(
                url,
                against: SEAEnvironment.current,
                narrowedBy: allowlist
            )
            switch verdict {
            case .success:
                return FuzzRunResult(id: entry.id, entry: entry, outcome: .allowed)
            case .failure(let reason):
                return FuzzRunResult(id: entry.id, entry: entry, outcome: .blocked(reason))
            }
        }
    }

    @ViewBuilder
    private func verdictIcon(_ outcome: FuzzOutcome) -> some View {
        switch outcome {
        case .notRun:
            Image(systemName: "circle.dashed").foregroundColor(.secondary)
        case .allowed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .blocked:
            Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
        case .malformedURL:
            Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
        }
    }

    private func verdictText(_ outcome: FuzzOutcome) -> String {
        switch outcome {
        case .notRun:
            return "not run"
        case .allowed:
            return "ALLOWED — unexpected for a hostile-corpus entry"
        case .blocked(let reason):
            return "blocked (\(reason.rawValue))"
        case .malformedURL:
            return "blocked (malformed — URL(string:) failed to parse)"
        }
    }
}
