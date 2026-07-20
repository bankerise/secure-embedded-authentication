import XCTest
@testable import SEACore

/// Contract §4: exactly one of `onCaptured`/`onCancelled`/`onError` fires,
/// exactly once, ever. `SEATerminalGuard` is the standalone primitive
/// `SEAAuthViewController` uses to enforce this; tested directly here so the
/// invariant is deterministic and independent of UIKit/WebKit timing.
final class SEATerminalGuardTests: XCTestCase {
    func test_firstCall_runsTheAction() {
        let guardObject = SEATerminalGuard()
        var ran = false
        let didFire = guardObject.fireOnce { ran = true }
        XCTAssertTrue(didFire)
        XCTAssertTrue(ran)
        XCTAssertTrue(guardObject.hasFired)
    }

    func test_secondCall_isANoOp() {
        let guardObject = SEATerminalGuard()
        guardObject.fireOnce { }
        var ranSecondTime = false
        let didFireSecond = guardObject.fireOnce { ranSecondTime = true }
        XCTAssertFalse(didFireSecond)
        XCTAssertFalse(ranSecondTime)
    }

    func test_repeatedCallsAfterFirst_areAllNoOps() {
        let guardObject = SEATerminalGuard()
        var runCount = 0
        for _ in 0..<10 {
            guardObject.fireOnce { runCount += 1 }
        }
        XCTAssertEqual(runCount, 1)
    }

    /// Simulates three competing terminal paths (capture / cancel / error)
    /// racing against the same guard, in every possible ordering, and
    /// asserts exactly one of them ever runs.
    func test_exactlyOneOfThreeCompetingCallbacksEverFires() {
        let orderings: [[String]] = [
            ["captured", "cancelled", "error"],
            ["cancelled", "captured", "error"],
            ["error", "captured", "cancelled"],
            ["cancelled", "error", "captured"]
        ]

        for ordering in orderings {
            let guardObject = SEATerminalGuard()
            var firedNames: [String] = []

            for name in ordering {
                guardObject.fireOnce { firedNames.append(name) }
            }

            XCTAssertEqual(firedNames.count, 1, "ordering \(ordering) fired \(firedNames.count) times")
            XCTAssertEqual(firedNames.first, ordering.first, "ordering \(ordering): the first attempt should win")
        }
    }
}
