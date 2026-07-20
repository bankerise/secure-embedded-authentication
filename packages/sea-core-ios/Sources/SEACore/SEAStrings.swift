import Foundation

/// Localized copy for SEA's native UI (contract §9, spec §18.4/§19).
///
/// All strings are looked up from `Bundle.module` (the package's own
/// resource bundle), never from the host app's bundle or from web content.
enum SEAStrings {
    private static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle.module, comment: "")
    }

    static var loading: String { string("sea.loading") }
    static var actionRetry: String { string("sea.action.retry") }
    static var actionClose: String { string("sea.action.close") }
    static var captureWarning: String { string("sea.capture.warning") }

    static var errorNetworkTitle: String { string("sea.error.network.title") }
    static var errorNetworkMessage: String { string("sea.error.network.message") }

    static var errorTimeoutTitle: String { string("sea.error.timeout.title") }
    static var errorTimeoutMessage: String { string("sea.error.timeout.message") }

    static var errorServerTitle: String { string("sea.error.server.title") }
    static var errorServerMessage: String { string("sea.error.server.message") }

    static var errorGenericTitle: String { string("sea.error.generic.title") }
    static var errorGenericMessage: String { string("sea.error.generic.message") }

    /// Maps a `SEAError` to the (title, message) pair for the native error
    /// state view. Only the error cases reachable in Phase 1 are given
    /// distinct copy; `.webauthnUnavailable` / `.killSwitched` are unreachable
    /// (see `SEAError`'s doc comments) and fall back to generic copy.
    static func copy(for error: SEAError) -> (title: String, message: String) {
        switch error {
        case .network:
            return (errorNetworkTitle, errorNetworkMessage)
        case .timeout:
            return (errorTimeoutTitle, errorTimeoutMessage)
        case .serverError:
            return (errorServerTitle, errorServerMessage)
        case .cancelled, .invalidAuthorizeURL, .webauthnUnavailable, .killSwitched:
            return (errorGenericTitle, errorGenericMessage)
        }
    }
}
