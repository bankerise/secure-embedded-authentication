import UIKit

/// Screen-recording capture policy (contract §8 / spec §17.1). Exposed on
/// `SEAConfig.capturePolicy`; default is `.warn`.
public enum SEACapturePolicy {
    case log
    case warn
    case blockInput
}

/// The pure decision half of screen security: given whether the screen is
/// currently being captured and the configured policy, what UI action
/// follows. Kept separate from `SEAScreenSecurityController` (which is all
/// UIKit/NotificationCenter plumbing) so the actual policy logic is
/// synchronously unit-testable.
enum SEACaptureAction: Equatable {
    case none
    case overlay(blocksInput: Bool)
}

enum SEAScreenSecurity {
    static func action(forCaptured isCaptured: Bool, policy: SEACapturePolicy) -> SEACaptureAction {
        guard isCaptured else { return .none }
        switch policy {
        case .log:
            return .none
        case .warn:
            return .overlay(blocksInput: false)
        case .blockInput:
            return .overlay(blocksInput: true)
        }
    }
}

/// Screen and process security (contract §8, spec §17.1).
///
/// - On `willResignActive`: installs an opaque branded cover view over the
///   host surface (defeats task-switcher snapshotting of auth content).
///   Removed on `didBecomeActive`.
/// - Observes `UIScreen.main.isCaptured` (+ `capturedDidChangeNotification`):
///   emits `AUTH_CAPTURE_DETECTED{kind: "recording"}` and applies
///   `capturePolicy`.
/// - Observes `userDidTakeScreenshotNotification`: emits
///   `AUTH_CAPTURE_DETECTED{kind: "screenshot"}`. Screenshots cannot be
///   blocked on iOS (spec §17.1) — this is log-only, always.
final class SEAScreenSecurityController {
    private weak var hostView: UIView?
    private let policy: SEACapturePolicy
    private var coverView: UIView?
    private var captureOverlayView: UIView?
    private var isObserving = false

    init(hostView: UIView, policy: SEACapturePolicy) {
        self.hostView = hostView
        self.policy = policy
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(screenCapturedDidChange), name: UIScreen.capturedDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenshotTaken), name: UIApplication.userDidTakeScreenshotNotification, object: nil)

        evaluateCaptureState()
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(self)
        removeCover()
        removeCaptureOverlay()
    }

    @objc private func appWillResignActive() {
        installCover()
    }

    @objc private func appDidBecomeActive() {
        removeCover()
    }

    @objc private func screenCapturedDidChange() {
        evaluateCaptureState()
    }

    @objc private func screenshotTaken() {
        SEATelemetry.record(name: SEATelemetryEventName.captureDetected, properties: ["kind": "screenshot"])
    }

    private func evaluateCaptureState() {
        let isCaptured = UIScreen.main.isCaptured
        let action = SEAScreenSecurity.action(forCaptured: isCaptured, policy: policy)

        if isCaptured {
            SEATelemetry.record(name: SEATelemetryEventName.captureDetected, properties: ["kind": "recording"])
        }

        switch action {
        case .none:
            removeCaptureOverlay()
        case .overlay(let blocksInput):
            installCaptureOverlay(blocksInput: blocksInput)
        }
    }

    private func installCover() {
        guard let hostView, coverView == nil else { return }
        let cover = UIView(frame: hostView.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .systemBackground

        let logo = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        logo.tintColor = .secondaryLabel
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 48),
            logo.heightAnchor.constraint(equalToConstant: 48)
        ])

        hostView.addSubview(cover)
        coverView = cover
    }

    private func removeCover() {
        coverView?.removeFromSuperview()
        coverView = nil
    }

    private func installCaptureOverlay(blocksInput: Bool) {
        guard let hostView else { return }
        if let existing = captureOverlayView {
            existing.isUserInteractionEnabled = blocksInput
            return
        }
        let overlay = UIView(frame: hostView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        overlay.isUserInteractionEnabled = blocksInput

        let label = UILabel()
        label.text = SEAStrings.captureWarning
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -24)
        ])

        hostView.addSubview(overlay)
        captureOverlayView = overlay
    }

    private func removeCaptureOverlay() {
        captureOverlayView?.removeFromSuperview()
        captureOverlayView = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
