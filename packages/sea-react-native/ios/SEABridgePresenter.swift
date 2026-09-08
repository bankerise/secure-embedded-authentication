import Foundation
import UIKit
import SEACore

/// `@objc` callback surface for `SeaReactNativeView.mm`. Every closure here
/// carries only primitive/bridgeable types — `SEACore`'s own types
/// (`SEACallbackParams`, `SEAError`) never cross into Objective-C++.
@objc(SEABridgeCallbacks)
public final class SEABridgeCallbacks: NSObject {
    let onCaptured: (String) -> Void
    let onCancelled: () -> Void
    let onError: (String, String?) -> Void

    @objc public init(
        onCaptured: @escaping (String) -> Void,
        onCancelled: @escaping () -> Void,
        onError: @escaping (String, String?) -> Void
    ) {
        self.onCaptured = onCaptured
        self.onCancelled = onCancelled
        self.onError = onError
    }
}

/// The entire bridge-side "logic": marshal primitive prop values into a
/// `SEAConfig`, call `SEASession.start`, and marshal the result back to
/// primitives. No authentication/navigation/validation logic lives here —
/// all of that is `SEACore`'s (spec §4.2, §7).
@objc(SEABridgePresenter)
public final class SEABridgePresenter: NSObject {
    @discardableResult
    @objc public static func start(
        fromAnchor anchorView: UIView,
        authorizeUrl: String,
        presentation: String,
        authMode: String,
        headerBackground: UIColor?,
        headerText: UIColor?,
        accent: UIColor?,
        closeIconTint: UIColor?,
        cornerRadius: NSNumber?,
        title: String,
        callbacks: SEABridgeCallbacks
    ) -> UIViewController? {
        guard let url = URL(string: authorizeUrl) else {
            callbacks.onError("invalid_authorize_url", "malformed authorizeUrl")
            return nil
        }
        guard let presenter = topMostViewController(from: anchorView) else {
            callbacks.onError("cancelled", "no presenter view controller available")
            return nil
        }

        var appearance = SEAAppearance.default
        if let headerBackground { appearance.headerBackground = headerBackground }
        if let headerText { appearance.headerText = headerText }
        if let accent { appearance.accent = accent }
        if let closeIconTint { appearance.closeIconTint = closeIconTint }
        if let cornerRadius { appearance.cornerRadius = CGFloat(truncating: cornerRadius) }
        appearance.title = title.isEmpty ? nil : title

        // Security knobs (allowedDomains, timeoutMs, callbackScheme, ports,
        // URL-length cap) are not bridge props: they are owned by the
        // platform config — `SEASecurityConfig.plist` read by
        // `SEAEnvironment.current` (§3.3) plus `SEAConfig`'s own defaults.
        // Host narrowing and timeout no longer apply from JS (spec §7.1/§7.3).
        let config = SEAConfig(
            authorizeURL: url,
            presentation: presentation == "fullscreen" ? .fullscreen : .sheet,
            appearance: appearance,
            authMode: authMode == "nativeBrowser" ? .nativeBrowser : .embedded
        )

        let seaCallbacks = SEASession.Callbacks(
            onCaptured: { params in
                callbacks.onCaptured(jsonString(from: params.raw))
            },
            onCancelled: {
                callbacks.onCancelled()
            },
            onError: { error in
                let (code, message) = taxonomy(for: error)
                callbacks.onError(code, message)
            }
        )

        return SEASession.start(config: config, from: presenter, callbacks: seaCallbacks)
    }

    @objc public static func dismiss(_ viewController: UIViewController) {
        viewController.dismiss(animated: true)
    }

    private static func jsonString(from raw: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Maps every `SEAError` case to the bridge's wire taxonomy verbatim
    /// (spec §7.2): network, timeout, cancelled, invalid_authorize_url,
    /// server_error, webauthn_unavailable, kill_switched.
    private static func taxonomy(for error: SEAError) -> (code: String, message: String?) {
        switch error {
        case .network(let underlying):
            return ("network", underlying)
        case .timeout:
            return ("timeout", nil)
        case .cancelled:
            return ("cancelled", nil)
        case .invalidAuthorizeURL(let reason):
            return ("invalid_authorize_url", reason.rawValue)
        case .serverError(let statusCode):
            return ("server_error", "\(statusCode)")
        case .webauthnUnavailable:
            return ("webauthn_unavailable", nil)
        case .killSwitched:
            return ("kill_switched", nil)
        }
    }

    private static func topMostViewController(from view: UIView) -> UIViewController? {
        guard var top = view.window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
