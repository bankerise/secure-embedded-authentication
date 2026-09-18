import Foundation

/// Authorize-URL integrity validation (contract §5, spec §6.2 — normative).
///
/// Rules are evaluated in order; all must pass. This is one of the two
/// security-perimeter components (the other being `SEANavigationPolicy`) and
/// is implemented as a pure, synchronous function for exhaustive table-driven
/// testing. Any ambiguity resolves to failure — fail closed.
public enum SEAAuthorizeURLValidator {
    public static func validate(
        _ url: URL,
        against env: SEAEnvironment,
        narrowedBy hostAllowlist: [String]
    ) -> Result<URL, SEAInvalidURLReason> {
        // Parse defensively via URLComponents so userinfo/port/host are read
        // from a structural parse rather than trusting `URL`'s lazily-parsed
        // convenience accessors. A URL that doesn't structurally parse is
        // `.malformed`, not `.host` — those are kept distinct reasons.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformed)
        }

        // 1. scheme is a member of env.allowedSchemes (case-insensitive).
        //    Default {"https"}; a host app may add "http" via
        //    SEASecurityConfig.plist's AllowedSchemes key for local dev
        //    behind a TLS-terminating reverse proxy (never in production).
        guard let scheme = components.scheme, env.allowedSchemes.contains(scheme.lowercased()) else {
            return .failure(.scheme)
        }

        // 2. no user, no password component.
        guard components.user == nil, components.password == nil else {
            return .failure(.userinfo)
        }

        // 3. port is nil or 443.
        if let port = components.port, port != 443 {
            return .failure(.port)
        }

        // 4. absoluteString.utf8.count <= 2048.
        guard url.absoluteString.utf8.count <= 2048 else {
            return .failure(.length)
        }

        // 5. host is non-nil, lowercased, and a member of the effective
        //    allowlist. Exact match only — no suffix matching. A trailing dot
        //    is stripped before comparison.
        //
        //    Host source is deliberately `url.host`, NOT `components.host`.
        //    The two apply opposite IDNA transforms, and only one is safe for
        //    a security comparison:
        //      • `url.host` yields the ASCII/punycode form the network stack
        //        actually resolves and connects to — "münchen.de" arrives as
        //        "xn--mnchen-3ya.de". This is the wire identity of the host.
        //      • `components.host` yields the IDNA-*decoded* display form and
        //        returns nil on invalid punycode — a display representation,
        //        not a wire one, and exactly the surface homograph/confusable
        //        attacks live on.
        //    Allowlisting against the wire form (contract §5: "compare on the
        //    punycode form; no IDNA decoding is performed") is the only choice
        //    that can't be fooled by a host that displays as one thing and
        //    connects to another. Punycode allowlist entries therefore match
        //    correctly, and a unicode host is compared as its own punycode
        //    encoding — never against a decoded form.
        //
        //    (`url.host` is soft-deprecated on iOS 16+ in favor of
        //    `host(percentEncoded:)`, which is iOS 16-only and returns the
        //    percent-encoded — not punycode — form. Neither fits: we keep
        //    `url.host` for the iOS 15 floor and the correct wire semantics.)
        guard let rawHost = url.host, !rawHost.isEmpty else {
            return .failure(.host)
        }
        let host = SEAEnvironment.normalizeHost(rawHost)
        let effectiveAllowlist = env.effectiveAllowlist(narrowedBy: hostAllowlist)
        guard effectiveAllowlist.contains(host) else {
            return .failure(.host)
        }

        return .success(url)
    }
}
