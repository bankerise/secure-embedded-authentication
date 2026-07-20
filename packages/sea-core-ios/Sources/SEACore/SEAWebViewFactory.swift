import WebKit

/// Hardened `WKWebView` construction (contract §7, spec §8.2 — normative).
///
/// HARD CONSTRAINTS enforced here and nowhere relaxed elsewhere in the
/// package:
/// - zero `WKUserScript`s, zero `WKScriptMessageHandler`s
/// - no `evaluateJavaScript` call anywhere in this package
/// - no reading of page DOM or content
public enum SEAWebViewFactory {
    /// Builds the hardened configuration described in contract §7 / spec §8.2.
    public static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()

        // Persistent, Safari-isolated datastore — required for the
        // persistent Keycloak SSO cookie (spec §11).
        configuration.websiteDataStore = .default()

        // Enforces the allowlist at the platform level. Consumers must
        // declare the auth + broker domains under `WKAppBoundDomains` in
        // their Info.plist — see the package README.
        configuration.limitsNavigationsToAppBoundDomains = true

        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Keycloak's login/passkey pages need content JavaScript. This is
        // page-authored JS running in the page's own context — categorically
        // different from a `WKUserScript` or a message handler injected by
        // this package, neither of which ever exists here.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // allowsInlineMediaPlayback intentionally left at its platform
        // default (contract §7 / spec §8.2: "default").

        return configuration
    }

    /// Builds a hardened `WKWebView` using `makeConfiguration()`.
    public static func makeWebView(frame: CGRect = .zero) -> WKWebView {
        let webView = WKWebView(frame: frame, configuration: makeConfiguration())
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }
}
