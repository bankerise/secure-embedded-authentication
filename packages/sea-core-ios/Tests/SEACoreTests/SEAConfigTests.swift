import XCTest
@testable import SEACore

final class SEAConfigTests: XCTestCase {
    func test_defaults_matchContract() {
        let config = SEAConfig(
            authorizeURL: URL(string: "https://auth.bank.com/auth")!
        )
        XCTAssertEqual(config.allowedDomains, [])
        if case .sheet = config.presentation {} else { XCTFail("default presentation should be .sheet") }
        XCTAssertEqual(config.timeoutMs, 120_000)
        if case .warn = config.capturePolicy {} else { XCTFail("default capturePolicy should be .warn") }
    }

    func test_appearanceDefault_isUsableColorsAndText() {
        let appearance = SEAAppearance.default
        XCTAssertNil(appearance.title)
        XCTAssertTrue(appearance.showsGrabber)
        XCTAssertEqual(appearance.cornerRadius, 16)
    }
}
