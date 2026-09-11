package com.bankerise.sea.core

/**
 * Enforces the contract §4 invariant: exactly one of
 * `onCaptured`/`onCancelled`/`onError` fires, exactly once, ever.
 *
 * Kept as a standalone, dependency-free type so the invariant itself is
 * directly and deterministically unit-testable, independent of WebView
 * runtime timing.
 */
internal class SEATerminalGuard {
    private var fired = false

    /**
     * Runs [action] only on the first call. Every subsequent call — no
     * matter which "terminal" path triggers it — is a silent no-op.
     * Returns whether [action] ran.
     */
    fun fireOnce(action: () -> Unit): Boolean {
        if (fired) return false
        fired = true
        action()
        return true
    }

    val hasFired: Boolean get() = fired
}
