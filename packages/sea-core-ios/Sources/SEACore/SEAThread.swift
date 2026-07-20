import Foundation

/// Threading guard for SEACore's public API (contract §2, spec §4.7 — normative).
///
/// All public API is main-thread-only. Every public entry point begins with
/// `SEAThread.assertMain()`. In debug builds this is an `assertionFailure`
/// (crashes the host app's test/debug run so misuse is caught immediately);
/// in release builds `assertionFailure` — and therefore this call — compiles
/// down to a no-op, matching the contract exactly.
public enum SEAThread {
    public static func assertMain(file: StaticString = #file, line: UInt = #line) {
        guard Thread.isMainThread else {
            assertionFailure("SEACore API must be called from the main thread", file: file, line: line)
            return
        }
    }
}
