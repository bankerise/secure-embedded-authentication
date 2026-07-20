import XCTest
@testable import SEACore

final class SEAScreenSecurityTests: XCTestCase {
    func test_notCaptured_neverProducesAnOverlay_regardlessOfPolicy() {
        for policy: SEACapturePolicy in [.log, .warn, .blockInput] {
            XCTAssertEqual(SEAScreenSecurity.action(forCaptured: false, policy: policy), .none)
        }
    }

    func test_captured_logPolicy_producesNoOverlay() {
        XCTAssertEqual(SEAScreenSecurity.action(forCaptured: true, policy: .log), .none)
    }

    func test_captured_warnPolicy_producesNonBlockingOverlay() {
        XCTAssertEqual(SEAScreenSecurity.action(forCaptured: true, policy: .warn), .overlay(blocksInput: false))
    }

    func test_captured_blockInputPolicy_producesBlockingOverlay() {
        XCTAssertEqual(SEAScreenSecurity.action(forCaptured: true, policy: .blockInput), .overlay(blocksInput: true))
    }
}
