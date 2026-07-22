import XCTest
@testable import SEACore

/// Spec §10.4 step 1 (pre-flight): `SEASession.makeViewController` must
/// route to the fallback path when the embedded WebAuthn ceremony is
/// unsupported, and to the normal embedded path otherwise. Exercised via the
/// `internal` `SEASession.viewController(for:environment:callbacks:embeddedCeremonySupported:)`
/// seam, which lets the decision be forced explicitly instead of depending
/// on whatever OS version actually runs the test (e.g. always-modern
/// Simulator/CI hosts, which would otherwise only ever exercise the
/// embedded branch).
final class SEASessionFallbackWiringTests: XCTestCase {
    private func makeConfig() -> SEAConfig {
        SEAConfig(authorizeURL: URL(string: "https://auth.bank.com/auth")!)
    }

    private func makeEnvironment() -> SEAEnvironment {
        SEAEnvironment(authDomains: ["auth.bank.com"], callbackScheme: "bkrmob")
    }

    private func makeCallbacks() -> SEASession.Callbacks {
        SEASession.Callbacks(onCaptured: { _ in }, onCancelled: {}, onError: { _ in })
    }

    func test_embeddedCeremonySupported_returnsTheEmbeddedViewController() {
        let vc = SEASession.viewController(
            for: makeConfig(),
            environment: makeEnvironment(),
            callbacks: makeCallbacks(),
            embeddedCeremonySupported: true
        )
        XCTAssertTrue(vc is SEAAuthViewController)
    }

    func test_embeddedCeremonyUnsupported_returnsTheFallbackEntryViewController() {
        let vc = SEASession.viewController(
            for: makeConfig(),
            environment: makeEnvironment(),
            callbacks: makeCallbacks(),
            embeddedCeremonySupported: false
        )
        XCTAssertTrue(vc is SEAFallbackEntryViewController)
    }

    func test_defaultParameter_usesTheRealCapabilityProbe() {
        // No explicit embeddedCeremonySupported: exercises the default
        // (SEAWebAuthnCapability.isEmbeddedCeremonySupported()), which on
        // any OS this test suite actually runs on today is above the
        // provisional iOS 16.0 floor, so the embedded path is chosen.
        let vc = SEASession.viewController(for: makeConfig(), environment: makeEnvironment(), callbacks: makeCallbacks())
        XCTAssertTrue(vc is SEAAuthViewController)
    }
}
