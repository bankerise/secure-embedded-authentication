import Foundation
import SEACore

/// Orchestrates "Start login": runs the §6.1 start sequence (real gateway or
/// mock, per the Config screen toggle), builds an SEAConfig from persisted
/// settings, and hands off to SEASession.start. This is glue code only — no
/// validation or navigation-policy logic lives here; that's entirely SEACore's.
@MainActor
final class LoginRunner: ObservableObject {
    @Published var isRunning = false
    @Published var lastStartError: String?

    private let settings: AppSettings
    private let resultStore: SessionResultStore
    private let tokenStore: SessionTokenStore

    init(
        settings: AppSettings = .shared,
        resultStore: SessionResultStore = .shared,
        tokenStore: SessionTokenStore = .shared
    ) {
        self.settings = settings
        self.resultStore = resultStore
        self.tokenStore = tokenStore
    }

    func startLogin() {
        guard !isRunning else { return }
        isRunning = true
        lastStartError = nil

        Task {
            defer { isRunning = false }
            do {
                let gateway = makeGateway()
                let result = try await gateway.startAuthorization(locale: nil)
                presentSEASession(with: result)
            } catch {
                lastStartError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    private func makeGateway() -> AuthGateway {
        if settings.useMockGateway {
            return MockGateway(redirectURLString: settings.mockRedirectURL)
        }
        return GatewayClient(baseURLString: settings.gatewayBaseURL)
            ?? MockGateway(redirectURLString: settings.mockRedirectURL)
    }

    private func presentSEASession(with startResult: GatewayStartResult) {
        // §21: authMode arrives from the gateway; EMBEDDED (or absent) -> SEA.
        // SYSTEM_BROWSER's classic in-app-browser path is explicitly out of
        // SEA's / this demo's scope (api-contract-ios-v1.md front matter).
        guard let presenter = TopViewControllerResolver.topMostViewController() else {
            lastStartError = "No presenter UIViewController available."
            return
        }

        let config = SEAConfig(
            authorizeURL: startResult.redirectURL,
            allowedDomains: settings.allowedDomainsArray,
            presentation: settings.presentation,
            appearance: .default,
            timeoutMs: settings.timeoutMs,
            authMode: settings.authMode
        )

        // Remember what Logout needs from this session: the authorize URL (to
        // derive Keycloak's logout endpoint) and whether it's the mock path
        // (only then do we exchange the code for an id_token, below).
        let authorizeURL = startResult.redirectURL
        let isMock = settings.useMockGateway
        tokenStore.beginSession(authorizeURL: authorizeURL, wasMock: isMock)

        let callbacks = SEASession.Callbacks(
            onCaptured: { [resultStore, tokenStore] params in
                resultStore.recordCaptured(params)
                // Mock path only: exchange the code for tokens so Logout has an
                // id_token_hint. The real gateway does this server-side (§6.4),
                // so the app never touches tokens there.
                guard isMock, let code = params.code else { return }
                tokenStore.beginExchange()
                // @MainActor so the store's @Published writes stay on main; the
                // exchange's network I/O still offloads inside URLSession.
                Task { @MainActor in
                    do {
                        let tokens = try await TokenExchangeClient().exchange(
                            code: code,
                            authorizeURL: authorizeURL,
                            codeVerifier: AppSettings.mockCodeVerifier
                        )
                        tokenStore.recordIdToken(tokens.idToken)
                    } catch {
                        tokenStore.recordExchangeFailure(
                            (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                        )
                    }
                }
            },
            onCancelled: { [resultStore] in
                resultStore.recordCancelled()
            },
            onError: { [resultStore] error in
                resultStore.recordError(error)
            }
        )

        SEASession.start(config: config, from: presenter, callbacks: callbacks)
    }
}
