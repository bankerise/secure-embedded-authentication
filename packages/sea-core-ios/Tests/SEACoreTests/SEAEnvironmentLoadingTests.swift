import XCTest
@testable import SEACore

/// Contract §3.3: `SEAEnvironment.current` is no longer compiled into
/// SEACore — it is loaded at runtime from a `SEASecurityConfig.plist`
/// bundled into the HOST APPLICATION's own target (`Bundle.main`). These
/// tests exercise the loader (`SEAEnvironment.load(from:)`, `internal` for
/// exactly this purpose) directly against test-fixture bundles, so they
/// don't need to fake `Bundle.main`.
final class SEAEnvironmentLoadingTests: XCTestCase {
    /// `load(from:)` reports failures through `SEAEnvironment.reportLoadFailure`
    /// rather than calling `assertionFailure` inline, so these tests — which
    /// deliberately drive every fail-closed path — can silence that reporter
    /// instead of tripping the Debug-build trap `assertionFailure` performs
    /// (that trap is the intended behavior for a real host app in Debug; it
    /// would just as surely crash the test run that verifies it). Swapped
    /// back to the real default in `tearDown` so no other test is affected.
    override func tearDown() {
        SEAEnvironment.reportLoadFailure = { assertionFailure($0) }
        super.tearDown()
    }

    private func silenceLoadFailureReporting() {
        SEAEnvironment.reportLoadFailure = { _ in }
    }

    // MARK: - Valid fixture, bundled as a real SPM test resource

    func test_validFixture_parsesIntoExpectedAuthDomainsAndCallbackScheme() {
        let env = SEAEnvironment.load(from: .module)
        XCTAssertEqual(env.callbackScheme, "bkrmob")
        XCTAssertEqual(env.authDomains, ["platform-keycloak.pres.proxym-it.net"])
    }

    // MARK: - Table-driven: every fail-closed path

    private struct Case {
        let name: String
        /// nil => write no plist file at all (bundle has none).
        let plistContents: [String: Any]?
    }

    private let failClosedCases: [Case] = [
        Case(name: "no matching plist file in the bundle", plistContents: nil),
        Case(
            name: "AuthDomains present but empty",
            plistContents: ["CallbackScheme": "bkrmob", "AuthDomains": []]
        ),
        Case(
            name: "CallbackScheme missing entirely",
            plistContents: ["AuthDomains": ["auth.bank.com"]]
        ),
        Case(
            name: "CallbackScheme empty string",
            plistContents: ["CallbackScheme": "", "AuthDomains": ["auth.bank.com"]]
        ),
        Case(
            name: "CallbackScheme wrong type",
            plistContents: ["CallbackScheme": 42, "AuthDomains": ["auth.bank.com"]]
        ),
        Case(
            name: "AuthDomains missing entirely",
            plistContents: ["CallbackScheme": "bkrmob"]
        ),
        Case(
            name: "AuthDomains wrong type",
            plistContents: ["CallbackScheme": "bkrmob", "AuthDomains": "not-an-array"]
        )
    ]

    func test_everyMalformedOrMissingCase_failsClosed() {
        silenceLoadFailureReporting()

        for testCase in failClosedCases {
            let bundle = makeTempBundle(plistContents: testCase.plistContents)
            let env = SEAEnvironment.load(from: bundle)
            XCTAssertEqual(env.authDomains, [], testCase.name)
            XCTAssertEqual(env.callbackScheme, "", testCase.name)
        }
    }

    func test_nonDictionaryTopLevelPlist_failsClosed() {
        silenceLoadFailureReporting()

        let bundle = makeTempBundle(rawPlistArray: ["not", "a", "dictionary"])
        let env = SEAEnvironment.load(from: bundle)
        XCTAssertEqual(env.authDomains, [])
        XCTAssertEqual(env.callbackScheme, "")
    }

    // MARK: - Helpers

    /// Builds a throwaway on-disk "bundle" (just a directory `Bundle(path:)`
    /// can look resources up in) containing either a `SEASecurityConfig.plist`
    /// with the given contents, or no plist at all when `plistContents` is nil.
    private func makeTempBundle(plistContents: [String: Any]?) -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SEAEnvironmentLoadingTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let plistContents {
            let url = dir.appendingPathComponent("SEASecurityConfig.plist")
            let data = try! PropertyListSerialization.data(
                fromPropertyList: plistContents,
                format: .xml,
                options: 0
            )
            try! data.write(to: url)
        }

        return Bundle(path: dir.path)!
    }

    private func makeTempBundle(rawPlistArray: [Any]) -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SEAEnvironmentLoadingTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("SEASecurityConfig.plist")
        let data = try! PropertyListSerialization.data(
            fromPropertyList: rawPlistArray,
            format: .xml,
            options: 0
        )
        try! data.write(to: url)

        return Bundle(path: dir.path)!
    }
}
