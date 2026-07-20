import Foundation

/// Enforces the contract §4 invariant: exactly one of
/// `onCaptured`/`onCancelled`/`onError` fires, exactly once, ever.
///
/// Kept as a standalone, dependency-free type so the invariant itself is
/// directly and deterministically unit-testable, independent of UIKit/WebKit
/// runtime timing.
final class SEATerminalGuard {
    private var fired = false

    /// Runs `action` only on the first call. Every subsequent call — no
    /// matter which "terminal" path triggers it — is a silent no-op.
    /// Returns whether `action` ran.
    @discardableResult
    func fireOnce(_ action: () -> Void) -> Bool {
        guard !fired else { return false }
        fired = true
        action()
        return true
    }

    var hasFired: Bool { fired }
}
