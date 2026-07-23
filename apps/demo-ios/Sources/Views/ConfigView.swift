import SwiftUI
import SEACore

/// The app's root screen (per task brief). Lets the tester set and persist
/// every knob SEAConfig / the gateway client needs, and drives "Start login".
struct ConfigView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var runner: LoginRunner
    @StateObject private var logoutRunner = LogoutRunner()
    @ObservedObject private var tokenStore = SessionTokenStore.shared

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
                    // Not editable: the callback scheme is no longer a
                    // per-session SEAConfig knob — it's owned by
                    // SEAEnvironment, loaded once from this app's bundled
                    // SEASecurityConfig.plist (api-contract-ios-v1.md §3.3).
                    // Shown here read-only so the tester can still see
                    // what's actually enforced.
                    HStack {
                        Text("Callback scheme")
                        Spacer()
                        Text("\(SEAEnvironment.current.callbackScheme) (from SEASecurityConfig.plist)")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
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

                Section {
                    Button {
                        logoutRunner.logout()
                    } label: {
                        if logoutRunner.isLoggingOut {
                            HStack {
                                ProgressView()
                                Text("Logging out…")
                            }
                        } else {
                            Text("Logout")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(logoutRunner.isLoggingOut)

                    if let status = tokenStore.status {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    if let message = logoutRunner.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    if let logoutURL = logoutRunner.gatewayLogoutURL {
                        Text(logoutURL)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Logout")
                } footer: {
                    Text(settings.useMockGateway
                         ? "Mock: RP-initiated logout straight to Keycloak using the id_token from the last login (invalidates the SSO session server-side)."
                         : "Real: POST /gw/logout returns a Keycloak logout URL enriched with id_token_hint, to be called separately from the app.")
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
