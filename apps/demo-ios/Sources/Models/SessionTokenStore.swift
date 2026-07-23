import Foundation

/// Holds what the Logout button needs from the last completed login:
///  - the authorize URL SEACore loaded (to derive Keycloak's logout endpoint),
///  - whether it was the mock path,
///  - the `id_token` obtained via the mock-only token exchange, and
///  - a human-readable status line for the Config screen.
///
/// Demo harness only. A real integrator never stashes tokens in the app; the
/// gateway owns them (§6.4). This is populated only on the mock path (and used
/// only to demonstrate RP-initiated logout).
///
/// Plain `ObservableObject` (not `@MainActor`), matching `SessionResultStore`:
/// it's mutated from SEACore's terminal callback, which always fires on the
/// main thread (`SEAThread.assertMain`), so `@Published` writes land on main.
final class SessionTokenStore: ObservableObject {
    static let shared = SessionTokenStore()

    @Published private(set) var authorizeURL: URL?
    @Published private(set) var wasMock = false
    @Published private(set) var idToken: String?
    @Published private(set) var status: String?

    private init() {}

    /// Called when a session is presented, before the outcome is known.
    func beginSession(authorizeURL: URL, wasMock: Bool) {
        self.authorizeURL = authorizeURL
        self.wasMock = wasMock
        self.idToken = nil
        self.status = wasMock
            ? "Awaiting capture…"
            : "Real gateway — logout goes through POST /gw/logout."
    }

    func beginExchange() {
        status = "Exchanging code for tokens…"
    }

    func recordIdToken(_ token: String) {
        idToken = token
        status = "id_token acquired \(Self.now()) — ready to logout."
    }

    func recordExchangeFailure(_ message: String) {
        idToken = nil
        status = "Token exchange failed: \(message)"
    }

    func clear() {
        authorizeURL = nil
        wasMock = false
        idToken = nil
        status = nil
    }

    private static func now() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
