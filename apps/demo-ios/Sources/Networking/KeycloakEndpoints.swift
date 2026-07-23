import Foundation

/// Small URL helpers for deriving sibling Keycloak OIDC endpoints (token,
/// logout) and reading query params off an authorize URL.
///
/// Demo/test harness only — a real integrator never reconstructs these from
/// the authorize URL; the gateway owns the token exchange and logout (§6.4).
/// Here it lets the *mock* path (which talks straight to Keycloak with a known
/// PKCE verifier) complete a real code→token exchange and an RP-initiated
/// logout without a gateway in the loop.
extension URL {
    /// Given a Keycloak authorize endpoint
    /// (`…/protocol/openid-connect/auth?…`), derive a sibling endpoint by
    /// swapping the trailing `auth` path component — e.g. `"token"` →
    /// `…/protocol/openid-connect/token`, `"logout"` →
    /// `…/protocol/openid-connect/logout`. Query/fragment are dropped.
    /// Returns nil if the path doesn't end in `/auth`.
    func keycloakSiblingEndpoint(_ name: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        guard components.path.hasSuffix("/auth") else { return nil }
        components.path = String(components.path.dropLast("/auth".count)) + "/" + name
        return components.url
    }

    /// First value for a query item (URL-decoded), or nil.
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
