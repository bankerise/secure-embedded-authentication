import Foundation

/// Outcome of a navigation decision (contract §6 — normative).
public enum SEANavigationDecision: Equatable {
    /// The navigating URL matched `callbackScheme`. The navigation MUST be
    /// cancelled and never dispatched to the OS; `raw` is the verbatim query
    /// parameter extraction to deliver via `onCaptured`.
    case capture([String: String])
    /// The navigation is permitted to proceed.
    case allow
    /// The navigation MUST be cancelled. `reason` is a coarse, non-PII
    /// symbolic string (e.g. "scheme_not_allowed") — it never contains a raw
    /// host or URL, so it is always safe to fold directly into telemetry
    /// alongside a separately-computed `host_hash`.
    case block(reason: String)
}

/// Everything the navigation policy needs to know about one navigation
/// request. Constructing this from `WKNavigationAction`/`WKFrameInfo`/
/// `webView.url` is the delegate's only job — the decision itself lives here.
public struct SEANavigationRequest: Equatable {
    public let url: URL
    public let isMainFrame: Bool
    /// Host of the frame's currently-committed page, normalized. `nil` when
    /// nothing has committed yet (the initial load).
    public let currentPageHost: String?

    public init(url: URL, isMainFrame: Bool, currentPageHost: String?) {
        self.url = url
        self.isMainFrame = isMainFrame
        self.currentPageHost = currentPageHost.map(SEAEnvironment.normalizeHost)
    }
}

/// Navigation policy (contract §6, spec §7.3 — normative).
///
/// A pure, synchronous decision function taking a URL + frame info and
/// returning an `SEANavigationDecision`. `WKNavigationDelegate` is a thin
/// caller of this — all the interesting logic (and all the interesting
/// tests) live here, off the WebKit runtime.
///
/// Evaluated in this exact order, fail closed on any ambiguity:
/// 1. Callback-scheme match preempts everything → `.capture`.
/// 2. `about:blank` for the initial frame → `.allow`.
/// 3. scheme in `env.allowedSchemes` + host in the effective allowlist +
///    (main frame OR same-origin subresource) → `.allow`.
/// 4. Everything else → `.block`.
public enum SEANavigationPolicy {
    public static func decide(
        for request: SEANavigationRequest,
        environment env: SEAEnvironment,
        hostAllowlist: [String]
    ) -> SEANavigationDecision {
        let scheme = (request.url.scheme ?? "").lowercased()

        // 1. Callback-scheme match preempts everything, including malformed
        //    or otherwise-suspicious URLs — it never reaches the OS.
        if !scheme.isEmpty, scheme == env.callbackScheme.lowercased() {
            let params = SEACallbackParams.extract(from: request.url)
            return .capture(params.raw)
        }

        // 2. about:blank for the initial frame (main frame, nothing committed
        //    yet) is allowed — this is the WKWebView-internal blank document,
        //    not attacker-controlled content.
        if request.isMainFrame,
           request.currentPageHost == nil,
           request.url.absoluteString.lowercased() == "about:blank" {
            return .allow
        }

        // 3. allowed scheme + allowlisted host + (main frame or same-origin
        //    subresource). Consults `env.allowedSchemes` — the same set
        //    `SEAAuthorizeURLValidator` checks the authorize URL against —
        //    rather than hardcoding "https", so a host app that opted into
        //    "http" for local dev (SEASecurityConfig.plist's AllowedSchemes)
        //    doesn't have its very first navigation silently blocked here.
        guard env.allowedSchemes.contains(scheme) else {
            return .block(reason: "scheme_not_allowed")
        }
        guard let rawHost = request.url.host, !rawHost.isEmpty else {
            return .block(reason: "missing_host")
        }
        let host = SEAEnvironment.normalizeHost(rawHost)
        let effectiveAllowlist = env.effectiveAllowlist(narrowedBy: hostAllowlist)
        guard effectiveAllowlist.contains(host) else {
            return .block(reason: "host_not_allowlisted")
        }

        if request.isMainFrame {
            return .allow
        }

        // Subresource loads must additionally be same-origin as the
        // currently-committed page — being in the allowlist is necessary but
        // not sufficient for a subresource, since a main-frame navigation may
        // legitimately hop between allowlisted domains (e.g. broker IdPs)
        // while a subresource load should not be able to pull content
        // cross-origin between two otherwise-allowlisted domains.
        if let currentHost = request.currentPageHost, currentHost == host {
            return .allow
        }
        return .block(reason: "subresource_cross_origin")
    }
}
