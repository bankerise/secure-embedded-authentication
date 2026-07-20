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

    init(settings: AppSettings = .shared, resultStore: SessionResultStore = .shared) {
        self.settings = settings
        self.resultStore = resultStore
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
            callbackScheme: settings.callbackScheme,
            allowedDomains: settings.allowedDomainsArray,
            presentation: settings.presentation,
            appearance: .default,
            timeoutMs: settings.timeoutMs
        )

        let callbacks = SEASession.Callbacks(
            onCaptured: { [resultStore] params in
                resultStore.recordCaptured(params)
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
