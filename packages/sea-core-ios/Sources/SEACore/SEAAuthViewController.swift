import UIKit
import WebKit

/// The auth surface (spec §8.1 / contract §9): native header (back/title/
/// close), sheet or fullscreen presentation, a hardened `WKWebView`, native
/// loading/error states, screen security, and a session timeout.
///
/// Not part of the public contract surface — `SEASession.makeViewController`
/// returns it type-erased as `UIViewController` (contract §4). All the
/// security-relevant decision logic lives in `SEANavigationPolicy` and
/// `SEAAuthorizeURLValidator`; this type is a thin, mostly-UIKit caller of
/// both, plus the terminal-callback bookkeeping.
final class SEAAuthViewController: UIViewController {
    private let config: SEAConfig
    private let environment: SEAEnvironment
    private let callbacks: SEASession.Callbacks

    private let webView: WKWebView
    private let headerView: SEAHeaderView
    private let loadingView: SEALoadingView
    private var errorView: SEAErrorStateView?
    private var screenSecurity: SEAScreenSecurityController?

    /// Guards the "exactly one terminal callback, exactly once, ever"
    /// invariant (contract §4). See `SEATerminalGuard`.
    private let terminalGuard = SEATerminalGuard()
    private var hasFinishedFirstLoad = false
    private var currentDisplayedError: SEAError?
    private var currentPageHost: String?
    private var loadStartDate: Date?
    private var timeoutTimer: Timer?
    private var kvoTokens: [NSKeyValueObservation] = []

    init(config: SEAConfig, environment: SEAEnvironment, callbacks: SEASession.Callbacks) {
        self.config = config
        self.environment = environment
        self.callbacks = callbacks
        self.webView = SEAWebViewFactory.makeWebView()
        self.headerView = SEAHeaderView(appearance: config.appearance, presentation: config.presentation)
        self.loadingView = SEALoadingView(accent: config.appearance.accent)
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
        buildLayout()

        screenSecurity = SEAScreenSecurityController(hostView: view, policy: config.capturePolicy)
        screenSecurity?.startObserving()

        setUpPresentation()
        observeWebView()

        isModalInPresentation = true
        showLoading()

        loadStartDate = Date()
        SEATelemetry.record(name: SEATelemetryEventName.webviewOpened, properties: [
            "mode": "embedded",
            "prewarmed": "true",
            "locale": Locale.current.identifier
        ])

        webView.load(URLRequest(url: config.authorizeURL))
        startTimeoutTimer()
    }

    // MARK: - Layout

    private func buildLayout() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.onBack = { [weak self] in self?.headerBackTapped() }
        headerView.onClose = { [weak self] in self?.headerCloseTapped() }
        view.addSubview(headerView)

        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 52),

            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingView.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
    }

    private func setUpPresentation() {
        presentationController?.delegate = self
        guard config.presentation == .sheet, let sheet = sheetPresentationController else { return }
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = config.appearance.showsGrabber
        sheet.preferredCornerRadius = config.appearance.cornerRadius
    }

    private func observeWebView() {
        kvoTokens.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            self?.headerView.setBackVisible(webView.canGoBack)
        })
        // POST-redirect backstop (contract §6): the callback URL is also
        // checked here via KVO, independent of decidePolicyFor/didCommit.
        kvoTokens.append(webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            self?.checkCallbackBackstop(url: webView.url)
        })
    }

    // MARK: - Loading / error UI

    private func showLoading() {
        loadingView.isHidden = false
    }

    private func hideLoading() {
        loadingView.isHidden = true
    }

    private func showError(_ error: SEAError) {
        currentDisplayedError = error
        hideLoading()
        let copy = SEAStrings.copy(for: error)
        let view = errorView ?? makeErrorView()
        view.configure(title: copy.title, message: copy.message)
        view.isHidden = false
        isModalInPresentation = false
    }

    private func clearError() {
        currentDisplayedError = nil
        errorView?.isHidden = true
    }

    private func makeErrorView() -> SEAErrorStateView {
        let errorStateView = SEAErrorStateView()
        errorStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.onRetry = { [weak self] in self?.retryLoad() }
        view.addSubview(errorStateView)
        NSLayoutConstraint.activate([
            errorStateView.topAnchor.constraint(equalTo: webView.topAnchor),
            errorStateView.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            errorStateView.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            errorStateView.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        ])
        errorView = errorStateView
        return errorStateView
    }

    private func retryLoad() {
        clearError()
        showLoading()
        isModalInPresentation = true
        loadStartDate = Date()
        webView.load(URLRequest(url: config.authorizeURL))
    }

    // MARK: - Header actions

    private func headerBackTapped() {
        webView.goBack()
    }

    private func headerCloseTapped() {
        if let error = currentDisplayedError {
            terminalError(error)
        } else {
            terminalCancel()
        }
    }

    // MARK: - Timeout

    private func startTimeoutTimer() {
        let seconds = Double(config.timeoutMs) / 1000.0
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            SEATelemetry.record(name: SEATelemetryEventName.timeout, properties: ["stage": self.currentStage()])
            self.terminalError(.timeout)
        }
    }

    private func currentStage() -> String {
        if hasFinishedFirstLoad { return "loaded" }
        if currentDisplayedError != nil { return "error" }
        return "loading"
    }

    // MARK: - Navigation policy application

    func apply(decision: SEANavigationDecision, url: URL, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch decision {
        case .capture(let raw):
            decisionHandler(.cancel)
            handleCapture(raw)
        case .allow:
            decisionHandler(.allow)
        case .block(let reason):
            decisionHandler(.cancel)
            emitNavBlocked(scheme: url.scheme ?? "", host: url.host, reason: reason)
        }
    }

    func emitNavBlocked(scheme: String, host: String?, reason: String) {
        // AUTH_NAV_BLOCKED carries only `scheme` and `host_hash` (contract
        // §3.6/§20.1) — the internal `reason` string is deliberately never
        // forwarded into telemetry properties.
        var properties = ["scheme": scheme]
        if let host {
            properties["host_hash"] = SEATelemetry.hostHash(host)
        }
        SEATelemetry.record(name: SEATelemetryEventName.navBlocked, properties: properties)
    }

    func checkCallbackBackstop(url: URL?) {
        guard let url, (url.scheme ?? "").lowercased() == environment.callbackScheme.lowercased() else { return }
        let params = SEACallbackParams.extract(from: url)
        handleCapture(params.raw)
    }

    func handleNavigationFailure(_ error: Error) {
        // Post-terminal suppression (contract §4): once a terminal outcome has
        // fired (typically capture), the session is over and this VC is
        // dismissing. A late navigation failure — most commonly WebKit
        // reporting the *cancelled* `bkrmob://` callback redirect as something
        // other than NSURLErrorCancelled (e.g. NSURLErrorUnsupportedURL /
        // WebKitErrorDomain) — must never record AUTH_FAILED or flash an error
        // modal over a successful login. The capture always lands first (it is
        // synchronous in `apply(decision:)`; this delegate callback is a later
        // main-thread turn), so `hasFired` is reliably set by the time we get
        // here in that race.
        guard !terminalGuard.hasFired else { return }

        let nsError = error as NSError
        // WebKit reports our own decidePolicyFor(.cancel) calls (callback
        // capture / navigation block) as NSURLErrorCancelled. That is not a
        // real failure and must never surface as a native error state.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        SEATelemetry.record(name: SEATelemetryEventName.failed, properties: ["code": "network"])
        showError(.network(underlying: nsError.localizedDescription))
    }

    func handleServerError(statusCode: Int) {
        // Same post-terminal suppression as handleNavigationFailure: never
        // surface a 5xx over an already-terminal session.
        guard !terminalGuard.hasFired else { return }
        SEATelemetry.record(name: SEATelemetryEventName.failed, properties: ["code": "server"])
        showError(.serverError(statusCode: statusCode))
    }

    // MARK: - Terminal callbacks (exactly one, exactly once, ever)

    private func fireTerminalOnce(_ action: () -> Void) {
        SEAThread.assertMain()
        let didFire = terminalGuard.fireOnce(action)
        guard didFire else { return }
        dismissSelf()
    }

    func handleCapture(_ raw: [String: String]) {
        fireTerminalOnce { [weak self] in
            guard let self else { return }
            let ms = self.loadStartDate.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
            SEATelemetry.record(name: SEATelemetryEventName.completed, properties: [
                "total_ms": String(ms),
                "method_class": "embedded"
            ])
            self.callbacks.onCaptured(SEACallbackParams(raw: raw))
        }
    }

    private func terminalCancel() {
        fireTerminalOnce { [weak self] in
            guard let self else { return }
            SEATelemetry.record(name: SEATelemetryEventName.cancelled, properties: ["stage": self.currentStage()])
            self.callbacks.onCancelled()
        }
    }

    private func terminalError(_ error: SEAError) {
        fireTerminalOnce { [weak self] in
            guard let self else { return }
            self.callbacks.onError(error)
        }
    }

    private func dismissSelf() {
        screenSecurity?.stopObserving()
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        kvoTokens.forEach { $0.invalidate() }
        kvoTokens.removeAll()
        guard presentingViewController != nil else { return }
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - WKNavigationDelegate

extension SEAAuthViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let request = SEANavigationRequest(url: url, isMainFrame: isMainFrame, currentPageHost: currentPageHost)
        let decision = SEANavigationPolicy.decide(for: request, environment: environment, hostAllowlist: config.allowedDomains)
        apply(decision: decision, url: url, decisionHandler: decisionHandler)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Downloads are always denied (contract §6 / spec §8.2): any response
        // WebKit cannot render inline is refused outright rather than
        // becoming a WKDownload.
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            return
        }
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           http.statusCode >= 500 {
            decisionHandler(.cancel)
            handleServerError(statusCode: http.statusCode)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let host = webView.url?.host {
            currentPageHost = SEAEnvironment.normalizeHost(host)
        }
        // POST-redirect backstop (contract §6.3 / spec §6.3).
        checkCallbackBackstop(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasFinishedFirstLoad = true
        hideLoading()
        clearError()
        isModalInPresentation = false

        let ms: Int
        if let start = loadStartDate {
            ms = Int(Date().timeIntervalSince(start) * 1000)
        } else {
            ms = 0
        }
        let pageClass = SEATelemetry.pageClass(forPath: webView.url?.path ?? "")
        SEATelemetry.record(name: SEATelemetryEventName.pageLoaded, properties: [
            "page_class": pageClass.rawValue,
            "ms": String(ms)
        ])

        checkCallbackBackstop(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default system handling only. Never trust an invalid certificate;
        // no debug bypass. (Pinning is Phase 2, spec §15.)
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKUIDelegate

extension SEAAuthViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Never open externally: allowlisted targets load in the same
        // WebView; everything else is blocked. This method always returns
        // nil (contract §6).
        guard let url = navigationAction.request.url else { return nil }
        let request = SEANavigationRequest(url: url, isMainFrame: true, currentPageHost: currentPageHost)
        let decision = SEANavigationPolicy.decide(for: request, environment: environment, hostAllowlist: config.allowedDomains)
        switch decision {
        case .allow:
            webView.load(navigationAction.request)
        case .capture(let raw):
            handleCapture(raw)
        case .block(let reason):
            emitNavBlocked(scheme: url.scheme ?? "", host: url.host, reason: reason)
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}

// MARK: - WKDownloadDelegate (denies all downloads, contract §6)

extension SEAAuthViewController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        completionHandler(nil)
        download.cancel()
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension SEAAuthViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Swipe-to-dismiss = onCancelled (contract §9). Disabled while a
        // navigation is in flight via `isModalInPresentation`, so this only
        // fires when a dismiss was actually permitted.
        terminalCancel()
    }
}

// MARK: - Title sanitization (contract §9 — pure, testable)

/// Sanitizes a live page title for header display: single line, max 64
/// characters, never interpreted as markup (it is only ever set as a
/// `UILabel.text`, never HTML).
enum SEATitleSanitizer {
    static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let singleLine = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 64 {
            return String(trimmed.prefix(64))
        }
        return trimmed
    }
}

// MARK: - Header view

private final class SEAHeaderView: UIView {
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    // Fullscreen presentation has no swipe-to-dismiss gesture (that's a
    // pageSheet/UISheetPresentationController affordance), so it's the only
    // mode that needs an explicit close control — sheet presentation relies
    // on swipe-to-dismiss instead (contract §9, presentationControllerDidDismiss).
    init(appearance: SEAAppearance, presentation: SEAPresentation) {
        super.init(frame: .zero)
        backgroundColor = appearance.headerBackground

        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        backButton.tintColor = appearance.closeIconTint
        backButton.isHidden = true
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.accessibilityLabel = "Back"

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = appearance.closeIconTint
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.accessibilityLabel = SEAStrings.actionClose
        closeButton.isHidden = presentation != .fullscreen

        for subview in [backButton, closeButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setBackVisible(_ visible: Bool) {
        backButton.isHidden = !visible
    }

    @objc private func backTapped() { onBack?() }
    @objc private func closeTapped() { onClose?() }
}

// MARK: - Loading view

private final class SEALoadingView: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    init(accent: UIColor) {
        super.init(frame: .zero)
        backgroundColor = .clear
        spinner.color = accent
        spinner.startAnimating()

        label.text = SEAStrings.loading
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Error state view

private final class SEAErrorStateView: UIView {
    var onRetry: (() -> Void)?

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        isHidden = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        retryButton.setTitle(SEAStrings.actionRetry, for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
    }

    @objc private func retryTapped() { onRetry?() }
}
