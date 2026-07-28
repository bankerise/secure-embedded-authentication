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
                    Picker("Presentation", selection: rendererModeBinding) {
                        Text("Sheet").tag(RendererMode.sheet)
                        Text("Fullscreen").tag(RendererMode.fullscreen)
                        Text("Browser").tag(RendererMode.browser)
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

    // UI-only merge of SEAConfig's two independent knobs (presentation,
    // authMode) into a single 3-way picker, so a tester can reach the §10.4
    // fallback (ASWebAuthenticationSession) without a separate control.
    // `.browser` means authMode = .nativeBrowser — presentation is
    // irrelevant on that path (the fallback runner ignores it) but a value
    // is still needed on AppSettings, so it's left unchanged.
    private enum RendererMode: Hashable {
        case sheet, fullscreen, browser
    }

    // SEAPresentation/SEAAuthMode (SEACore) have no documented
    // Equatable/Hashable conformance (SEAAuthMode does as of this writing,
    // but SEAPresentation doesn't), so rather than retroactively conforming
    // a contract type, this binds the segmented Picker to the plain
    // RendererMode enum above and translates at the edges.
    private var rendererModeBinding: Binding<RendererMode> {
        Binding(
            get: {
                switch settings.authMode {
                case .nativeBrowser: return .browser
                case .embedded:
                    switch settings.presentation {
                    case .fullscreen: return .fullscreen
                    case .sheet: return .sheet
                    }
                }
            },
            set: { mode in
                switch mode {
                case .sheet:
                    settings.authMode = .embedded
                    settings.presentation = .sheet
                case .fullscreen:
                    settings.authMode = .embedded
                    settings.presentation = .fullscreen
                case .browser:
                    settings.authMode = .nativeBrowser
                }
            }
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
