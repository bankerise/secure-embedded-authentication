import Foundation
import SEACore

/// Verbatim record of the last SEASession terminal outcome, for the results view.
/// This is a dev harness: showing raw captured params (including code/state) here
/// is intentional and correct per the task brief — it is NOT how a real
/// integrator would handle them (that's the gateway's job, §6.4).
enum SessionOutcome {
    case none
    case captured(raw: [String: String], at: Date)
    case cancelled(at: Date)
    case error(SEAError, at: Date)
}

final class SessionResultStore: ObservableObject {
    static let shared = SessionResultStore()

    @Published private(set) var outcome: SessionOutcome = .none

    private init() {}

    func recordCaptured(_ params: SEACallbackParams) {
        outcome = .captured(raw: params.raw, at: Date())
    }

    func recordCancelled() {
        outcome = .cancelled(at: Date())
    }

    func recordError(_ error: SEAError) {
        outcome = .error(error, at: Date())
    }

    func reset() {
        outcome = .none
    }
}

extension SEAError {
    /// Human-readable description for the results view. Not part of the contract —
    /// purely cosmetic mapping for the harness UI.
    var demoDescription: String {
        switch self {
        case .network(let underlying):
            return "network(\(underlying))"
        case .timeout:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .invalidAuthorizeURL(let reason):
            return "invalidAuthorizeURL(\(reason.rawValue))"
        case .serverError(let statusCode):
            return "serverError(\(statusCode))"
        case .webauthnUnavailable:
            return "webauthnUnavailable (Phase 2 — should not occur in Phase 1)"
        case .killSwitched:
            return "killSwitched (Phase 2 — should not occur in Phase 1)"
        }
    }
}
