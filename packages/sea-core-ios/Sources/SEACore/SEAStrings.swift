import Foundation

// `Bundle.module` is synthesized by SwiftPM and only exists when this file
// is compiled as part of an SPM target (`SWIFT_PACKAGE` is defined
// automatically in that case). The CocoaPods build of this same source
// (consumed by `sea-react-native`, see `SEACore.podspec`) has no such
// symbol — resources there land directly in this module's own bundle, so
// `Bundle(for:)` on a marker type declared in this module finds them.
#if SWIFT_PACKAGE
private let seaCoreResourceBundle = Bundle.module
#else
private final class SEACoreBundleToken {}
private let seaCoreResourceBundle = Bundle(for: SEACoreBundleToken.self)
#endif

/// Localized copy for SEA's native UI (contract §9, spec §18.4/§19).
///
/// All strings are looked up from SEACore's own resource bundle (SwiftPM's
/// `Bundle.module` or, under CocoaPods, this module's own bundle — see
/// above), never from the host app's bundle or from web content.
enum SEAStrings {
    private static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: seaCoreResourceBundle, comment: "")
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
    /// state view. `.webauthnUnavailable` is reachable (see `SEAError`'s doc
    /// comment) but only via `SEAFallbackAuthRunner`, which has no native
    /// error-state view of its own and fires `onError` directly — so it
    /// never actually reaches this function in practice today. `.killSwitched`
    /// remains unreachable (Phase 2, §21). Both fall back to generic copy
    /// here for taxonomy completeness.
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
