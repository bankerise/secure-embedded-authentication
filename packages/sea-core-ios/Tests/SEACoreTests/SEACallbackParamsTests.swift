import XCTest
@testable import SEACore

final class SEACallbackParamsTests: XCTestCase {
    func test_extractsAllParamsVerbatim() {
        let url = URL(string: "bankerise-auth://callback?code=abc123&state=xyz&session_state=sess1")!
        let params = SEACallbackParams.extract(from: url)
        XCTAssertEqual(params.code, "abc123")
        XCTAssertEqual(params.state, "xyz")
        XCTAssertEqual(params.sessionState, "sess1")
        XCTAssertEqual(params.raw.count, 3)
    }

    func test_errorShapedCallback_extractsErrorFields() {
        let url = URL(string: "bankerise-auth://callback?error=access_denied&error_description=User%20cancelled")!
        let params = SEACallbackParams.extract(from: url)
        XCTAssertEqual(params.error, "access_denied")
        XCTAssertEqual(params.errorDescription, "User cancelled")
        XCTAssertNil(params.code)
    }

    func test_emptyValuedKey_isPreservedAsEmptyString() {
        let url = URL(string: "bankerise-auth://callback?code=abc&flag&state=")!
        let params = SEACallbackParams.extract(from: url)
        XCTAssertEqual(params.raw["flag"], "")
        XCTAssertEqual(params.raw["state"], "")
        XCTAssertEqual(params.code, "abc")
    }

    func test_duplicateKey_lastValueWins() {
        let url = URL(string: "bankerise-auth://callback?code=first&code=second")!
        let params = SEACallbackParams.extract(from: url)
        XCTAssertEqual(params.code, "second")
    }

    func test_noQueryString_yieldsEmptyRaw() {
        let url = URL(string: "bankerise-auth://callback")!
        let params = SEACallbackParams.extract(from: url)
        XCTAssertTrue(params.raw.isEmpty)
        XCTAssertNil(params.code)
    }

    func test_rawInitializerRoundTrips() {
        let params = SEACallbackParams(raw: ["code": "abc", "state": "xyz"])
        XCTAssertEqual(params.code, "abc")
        XCTAssertEqual(params.state, "xyz")
        XCTAssertNil(params.sessionState)
        XCTAssertNil(params.error)
        XCTAssertNil(params.errorDescription)
    }
}
