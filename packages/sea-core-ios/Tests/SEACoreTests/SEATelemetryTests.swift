import XCTest
@testable import SEACore

final class SEATelemetryTests: XCTestCase {
    // MARK: - hostHash

    func test_hostHash_neverEqualsOrContainsTheRawHost() {
        let host = "auth.bank.com"
        let hash = SEATelemetry.hostHash(host)
        XCTAssertNotEqual(hash, host)
        XCTAssertFalse(hash.contains("auth"))
        XCTAssertFalse(hash.contains("bank"))
    }

    func test_hostHash_isSixteenLowercaseHexCharacters() {
        let hash = SEATelemetry.hostHash("auth.bank.com")
        XCTAssertEqual(hash.count, 16)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) })
    }

    func test_hostHash_isCaseInsensitiveOnInput() {
        XCTAssertEqual(SEATelemetry.hostHash("AUTH.BANK.COM"), SEATelemetry.hostHash("auth.bank.com"))
    }

    func test_hostHash_isDeterministic() {
        XCTAssertEqual(SEATelemetry.hostHash("auth.bank.com"), SEATelemetry.hostHash("auth.bank.com"))
    }

    func test_hostHash_differentHostsProduceDifferentHashes() {
        XCTAssertNotEqual(SEATelemetry.hostHash("auth.bank.com"), SEATelemetry.hostHash("evil.io"))
    }

    // MARK: - pageClass

    func test_pageClass_bucketsKnownPaths() {
        XCTAssertEqual(SEATelemetry.pageClass(forPath: "/realms/mobile/login-actions/authenticate"), .login)
        XCTAssertEqual(SEATelemetry.pageClass(forPath: "/webauthn/register"), .webauthn)
        XCTAssertEqual(SEATelemetry.pageClass(forPath: "/otp/verify"), .otp)
        XCTAssertEqual(SEATelemetry.pageClass(forPath: "/reset-credentials"), .reset)
        XCTAssertEqual(SEATelemetry.pageClass(forPath: "/broker/partner-idp/login"), .broker)
        XCTAssertEqual(SEATelemetry.pageClass(forPath: "/some/unrecognized/path"), .unknown)
    }

    func test_pageClass_neverReturnsTheRawPath() {
        // The contract requires paths be recorded only as a page_class
        // bucket. Assert the bucket's rawValue never equals or contains the
        // distinguishing raw path segment.
        let path = "/realms/mobile/login-actions/authenticate?sensitive=1"
        let bucket = SEATelemetry.pageClass(forPath: path).rawValue
        XCTAssertFalse(bucket.contains("sensitive"))
        XCTAssertFalse(bucket.contains("realms"))
    }

    // MARK: - record(name:properties:) routes through SEASession.telemetrySink

    private final class MockSink: SEATelemetrySink {
        var events: [SEAEvent] = []
        func record(_ event: SEAEvent) { events.append(event) }
    }

    override func tearDown() {
        SEASession.telemetrySink = nil
        super.tearDown()
    }

    func test_record_forwardsToRegisteredSink() {
        let sink = MockSink()
        SEASession.telemetrySink = sink

        SEATelemetry.record(name: "AUTH_TEST_EVENT", properties: ["a": "b"])

        XCTAssertEqual(sink.events.count, 1)
        XCTAssertEqual(sink.events.first?.name, "AUTH_TEST_EVENT")
        XCTAssertEqual(sink.events.first?.properties["a"], "b")
    }

    func test_record_withNoSinkRegistered_doesNothing() {
        SEASession.telemetrySink = nil
        // Should not crash with no sink registered.
        SEATelemetry.record(name: "AUTH_TEST_EVENT")
    }
}
