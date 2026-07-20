import UIKit
import WebKit

/// Entry point (contract §4).
///
/// Exactly one of `Callbacks.onCaptured` / `onCancelled` / `onError` fires
/// per session, exactly once. After a terminal callback fires, the
/// presented view controller dismisses itself and all further callbacks are
/// suppressed — enforced by `SEAAuthViewController`'s private terminal-state
/// guard.
public final class SEASession {
    public struct Callbacks {
        public var onCaptured: (SEACallbackParams) -> Void
        public var onCancelled: () -> Void
        public var onError: (SEAError) -> Void

        public init(
            onCaptured: @escaping (SEACallbackParams) -> Void,
            onCancelled: @escaping () -> Void,
            onError: @escaping (SEAError) -> Void
        ) {
            self.onCaptured = onCaptured
            self.onCancelled = onCancelled
            self.onError = onError
        }
    }

    public static weak var telemetrySink: SEATelemetrySink?

    /// Validates `config` (contract §6.2) and returns a presentable view
    /// controller. Throws `SEAError.invalidAuthorizeURL` before anything is
    /// loaded — no navigation, no WebView work happens on a rejected URL.
    public static func makeViewController(
        config: SEAConfig,
        callbacks: Callbacks
    ) throws -> UIViewController {
        SEAThread.assertMain()

        let environment = SEAEnvironment.current
        switch SEAAuthorizeURLValidator.validate(config.authorizeURL, against: environment, narrowedBy: config.allowedDomains) {
        case .failure(let reason):
            throw SEAError.invalidAuthorizeURL(reason: reason)
        case .success:
            break
        }

        return SEAAuthViewController(config: config, environment: environment, callbacks: callbacks)
    }

    /// Convenience: validate, build, and present from `presenter`. Returns
    /// `nil` if validation failed — in that case `onError` has already fired
    /// and nothing was presented.
    @discardableResult
    public static func start(
        config: SEAConfig,
        from presenter: UIViewController,
        callbacks: Callbacks
    ) -> UIViewController? {
        SEAThread.assertMain()

        do {
            let viewController = try makeViewController(config: config, callbacks: callbacks)
            presenter.present(viewController, animated: true)
            return viewController
        } catch let error as SEAError {
            callbacks.onError(error)
            return nil
        } catch {
            // Unreachable in practice — makeViewController only ever throws
            // SEAError — but fail closed rather than swallow silently.
            callbacks.onError(.invalidAuthorizeURL(reason: .malformed))
            return nil
        }
    }

    /// Spec §11.3 step 2 (datastore purge). Steps 1 (gateway logout), 3
    /// (native cookie jar / secure storage), and 4 (`AUTH_LOGOUT_COMPLETED`
    /// emission tied to the *overall* logout operation) belong to the host
    /// SDK, which orchestrates all four steps together.
    public static func purgeWebData(completion: @escaping () -> Void) {
        SEAThread.assertMain()
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                completion()
            }
        }
    }
}
