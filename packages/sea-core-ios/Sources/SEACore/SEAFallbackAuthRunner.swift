import UIKit
import AuthenticationServices

/// Runs the spec §10.4 fallback ceremony: hands the *entire* login attempt
/// to `ASWebAuthenticationSession(url:callbackURLScheme:)` using the same
/// gateway-issued authorize URL as the embedded path, and resolves through
/// the exact same `SEASession.Callbacks` contract. This path is
/// RFC-8252-clean by definition (spec §10.4 step 2).
///
/// Not part of the public contract surface — reached only via
/// `SEAFallbackEntryViewController`, itself returned type-erased as
/// `UIViewController` by `SEASession.makeViewController`.
final class SEAFallbackAuthRunner: NSObject {
    private let config: SEAConfig
    private let environment: SEAEnvironment
    private let callbacks: SEASession.Callbacks

    /// Same invariant as the embedded path (contract §4): exactly one of
    /// `onCaptured`/`onCancelled`/`onError` fires, exactly once. Reusing
    /// `SEATerminalGuard` rather than reimplementing the guard keeps the two
    /// paths' terminal semantics identical by construction.
    private let terminalGuard = SEATerminalGuard()

    private weak var presentingViewController: UIViewController?
    private var session: ASWebAuthenticationSession?
    private var startDate: Date?

    init(
        config: SEAConfig,
        environment: SEAEnvironment,
        callbacks: SEASession.Callbacks,
        presentingViewController: UIViewController
    ) {
        self.config = config
        self.environment = environment
        self.callbacks = callbacks
        self.presentingViewController = presentingViewController
    }

    /// Starts the fallback ceremony.
    ///
    /// Guard (contract §3.3 fail-closed / spec §10.4): if
    /// `environment.callbackScheme` is empty — the fail-closed value
    /// `SEAEnvironment.current` resolves to when the host app's
    /// `SEASecurityConfig.plist` is missing or malformed — there is no
    /// scheme an `ASWebAuthenticationSession` could ever be started with
    /// (an empty string is never dispatched back to us; the session would
    /// simply hang until timeout/user-cancel). Rather than start a session
    /// that can never succeed, fail closed immediately with
    /// `SEAError.webauthnUnavailable` — the one case that error is actually
    /// reachable (see its doc comment).
    func start() {
        SEAThread.assertMain()

        guard !environment.callbackScheme.isEmpty else {
            if terminalGuard.fireOnce({ [weak self] in self?.callbacks.onError(.webauthnUnavailable) }) {
                dismissEntry()
            }
            return
        }

        startDate = Date()
        let session = ASWebAuthenticationSession(
            url: config.authorizeURL,
            callbackURLScheme: environment.callbackScheme
        ) { [weak self] url, error in
            self?.handleCompletion(url: url, error: error)
        }
        session.presentationContextProvider = self
        // Explicitly non-ephemeral (also the framework default): shares
        // Safari's cookie jar, which is what lets a returning user's
        // Keycloak SSO session (spec §11.1) carry across embedded/fallback
        // attempts on this system path.
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    private func handleCompletion(url: URL?, error: Error?) {
        let didFire: Bool
        switch SEAFallbackAuthRunner.mapResult(url: url, error: error) {
        case .captured(let raw):
            didFire = terminalGuard.fireOnce { [weak self] in
                guard let self else { return }
                let ms = self.startDate.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                SEATelemetry.record(name: SEATelemetryEventName.completed, properties: [
                    "total_ms": String(ms),
                    "method_class": "fallback"
                ])
                self.callbacks.onCaptured(SEACallbackParams(raw: raw))
            }
        case .cancelled:
            didFire = terminalGuard.fireOnce { [weak self] in
                SEATelemetry.record(name: SEATelemetryEventName.cancelled, properties: ["stage": "fallback"])
                self?.callbacks.onCancelled()
            }
        case .error(let seaError):
            didFire = terminalGuard.fireOnce { [weak self] in
                SEATelemetry.record(name: SEATelemetryEventName.failed, properties: ["code": "network"])
                self?.callbacks.onError(seaError)
            }
        }
        // Contract §4 / SEASession doc: once a terminal callback has fired,
        // the presented view controller tears itself down. On the fallback
        // path that VC is the throwaway `SEAFallbackEntryViewController`
        // anchor — `ASWebAuthenticationSession` dismisses only its *own* Safari
        // UI, never our entry VC, so without this the blank anchor is left on
        // screen after the ceremony resolves.
        if didFire { dismissEntry() }
    }

    /// Mirror of the embedded path's `SEAAuthViewController.dismissSelf`:
    /// dismiss the `SEAFallbackEntryViewController` that `SEASession.start`
    /// presented (and which serves only as this session's presentation
    /// anchor) once the ceremony has reached a terminal outcome. Guarded on
    /// `presentingViewController != nil` so a never-presented anchor (or a
    /// double call) is a no-op.
    private func dismissEntry() {
        SEAThread.assertMain()
        guard let entry = presentingViewController, entry.presentingViewController != nil else { return }
        entry.dismiss(animated: true, completion: nil)
    }

    /// Pure `(url, error) -> outcome` mapping (spec §10.4 step 3), factored
    /// out of the `ASWebAuthenticationSession` completion handler so it is
    /// directly unit-testable without touching `ASWebAuthenticationSession`
    /// itself (which cannot be driven headlessly in a unit test).
    enum MappedResult: Equatable {
        case captured([String: String])
        case cancelled
        case error(SEAError)
    }

    static func mapResult(url: URL?, error: Error?) -> MappedResult {
        if let url {
            let params = SEACallbackParams.extract(from: url)
            return .captured(params.raw)
        }

        let nsError = error as NSError?
        if nsError?.domain == ASWebAuthenticationSessionErrorDomain,
           nsError?.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
            return .cancelled
        }

        return .error(.network(underlying: error?.localizedDescription ?? "unknown"))
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SEAFallbackAuthRunner: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentingViewController?.view.window ?? ASPresentationAnchor()
    }
}

/// Lightweight entry point returned by `SEASession.makeViewController` when
/// `SEAWebAuthnCapability` reports the embedded WKWebView ceremony is
/// unsupported (spec §10.4 step 1, pre-flight). Presents nothing of its own
/// — it exists only to have a `view.window` for
/// `ASWebAuthenticationSession`'s presentation anchor — and hands off to
/// `SEAFallbackAuthRunner` as soon as it is on screen.
///
/// `start(from:)` works unchanged for this type: `SEASession.start` simply
/// presents whatever `makeViewController` returns.
final class SEAFallbackEntryViewController: UIViewController {
    private let config: SEAConfig
    private let environment: SEAEnvironment
    private let callbacks: SEASession.Callbacks
    private let reason: String

    private var runner: SEAFallbackAuthRunner?
    private var hasStarted = false

    /// - Parameter reason: `"preflight"` or `"runtime"` (spec §20.1
    ///   `AUTH_WEBAUTHN_FALLBACK { reason: preflight|runtime }`).
    init(
        config: SEAConfig,
        environment: SEAEnvironment,
        callbacks: SEASession.Callbacks,
        reason: String
    ) {
        self.config = config
        self.environment = environment
        self.callbacks = callbacks
        self.reason = reason
        super.init(nibName: nil, bundle: nil)

        switch config.presentation {
        case .sheet:
            modalPresentationStyle = .pageSheet
        case .fullscreen:
            modalPresentationStyle = .fullScreen
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = config.appearance.headerBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true

        SEATelemetry.record(name: SEATelemetryEventName.webviewOpened, properties: [
            "mode": "fallback",
            "prewarmed": "false",
            "locale": Locale.current.identifier
        ])
        SEATelemetry.record(name: SEATelemetryEventName.webauthnFallback, properties: [
            "reason": reason,
            "os_version": SEAFallbackEntryViewController.osVersionString()
        ])

        let runner = SEAFallbackAuthRunner(
            config: config,
            environment: environment,
            callbacks: callbacks,
            presentingViewController: self
        )
        self.runner = runner
        runner.start()
    }

    static func osVersionString(
        _ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
