import SwiftUI
import SEACore

/// The app's root screen (per task brief). Lets the tester set and persist
/// every knob SEAConfig / the gateway client needs, and drives "Start login".
struct ConfigView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var runner: LoginRunner

    var body: some View {
        NavigationView {
            Form {
                Section("Gateway") {
                    TextField("Gateway base URL", text: $settings.gatewayBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Toggle("Use mock gateway", isOn: $settings.useMockGateway)
                    if settings.useMockGateway {
                        TextField("Mock redirectUrl", text: $settings.mockRedirectURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.footnote)
                    }
                }

                Section("SEAConfig") {
                    TextField("Callback scheme", text: $settings.callbackScheme)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Allowed domains (comma list)", text: $settings.allowedDomains)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Picker("Presentation", selection: presentationBinding) {
                        Text("Sheet").tag(false)
                        Text("Fullscreen").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Stepper(
                        "Timeout: \(settings.timeoutMs) ms",
                        value: $settings.timeoutMs,
                        in: 5_000...600_000,
                        step: 5_000
                    )
                }

                Section {
                    Button {
                        runner.startLogin()
                    } label: {
                        if runner.isRunning {
                            HStack {
                                ProgressView()
                                Text("Starting…")
                            }
                        } else {
                            Text("Start login")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(runner.isRunning)

                    if let error = runner.lastStartError {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section("Session data") {
                    Button("Purge web data", role: .destructive) {
                        purgeWebData()
                    }
                    if let purgeMessage {
                        Text(purgeMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("SEA Demo Config")
        }
        .navigationViewStyle(.stack)
    }

    @State private var purgeMessage: String?

    // SEAPresentation (SEACore) has no documented Equatable/Hashable
    // conformance, so rather than retroactively conforming a contract type
    // (risky: it could collide if the core adds conformance later), we bind
    // the segmented Picker to a plain Bool and translate at the edges.
    private var presentationBinding: Binding<Bool> {
        Binding(
            get: {
                switch settings.presentation {
                case .fullscreen: return true
                case .sheet: return false
                }
            },
            set: { settings.presentation = $0 ? .fullscreen : .sheet }
        )
    }

    private func purgeWebData() {
        purgeMessage = "Purging…"
        SEASession.purgeWebData {
            DispatchQueue.main.async {
                purgeMessage = "Purged at \(Date().formatted(date: .omitted, time: .standard))"
            }
        }
    }
}
