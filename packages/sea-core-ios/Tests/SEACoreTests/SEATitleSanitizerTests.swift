import XCTest
@testable import SEACore

final class SEATitleSanitizerTests: XCTestCase {
    func test_nilInput_yieldsNil() {
        XCTAssertNil(SEATitleSanitizer.sanitize(nil))
    }

    func test_emptyInput_yieldsNil() {
        XCTAssertNil(SEATitleSanitizer.sanitize(""))
        XCTAssertNil(SEATitleSanitizer.sanitize("   "))
    }

    func test_simpleTitle_passesThrough() {
        XCTAssertEqual(SEATitleSanitizer.sanitize("Login to Bank"), "Login to Bank")
    }

    func test_multilineTitle_collapsesToSingleLine() {
        let result = SEATitleSanitizer.sanitize("Login\nto\r\nBank\rNow")
        XCTAssertFalse(result?.contains("\n") ?? true)
        XCTAssertFalse(result?.contains("\r") ?? true)
        XCTAssertEqual(result, "Login to Bank Now")
    }

    func test_longTitle_truncatesTo64Characters() {
        let longTitle = String(repeating: "a", count: 100)
        let result = SEATitleSanitizer.sanitize(longTitle)
        XCTAssertEqual(result?.count, 64)
    }

    func test_exactly64Characters_isUnchanged() {
        let title = String(repeating: "b", count: 64)
        XCTAssertEqual(SEATitleSanitizer.sanitize(title), title)
    }

    func test_htmlLikeContent_isTreatedAsPlainTextNeverInterpreted() {
        // This is a sanitizer for display purposes only — it must not strip
        // or transform markup-looking content, since the caller only ever
        // assigns the result to a UILabel.text (never HTML-rendered).
        let title = "<script>alert(1)</script>"
        XCTAssertEqual(SEATitleSanitizer.sanitize(title), title)
    }
}
