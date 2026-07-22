import XCTest
@testable import SEACore

/// Spec §10.4 step 1 (pre-flight probe). `SEAWebAuthnCapability` is pure
/// version-comparison logic — no UIKit, no I/O — so it's exercised directly
/// here with injected `OperatingSystemVersion` values, independent of
/// whatever OS the test happens to run on.
final class SEAWebAuthnCapabilityTests: XCTestCase {
    private struct Case {
        let name: String
        let version: OperatingSystemVersion
        let expectedSupported: Bool
    }

    private let floor = SEAWebAuthnCapability.embeddedSupportFloor

    private lazy var cases: [Case] = [
        Case(
            name: "major version below floor",
            version: OperatingSystemVersion(majorVersion: floor.majorVersion - 1, minorVersion: 9, patchVersion: 9),
            expectedSupported: false
        ),
        Case(
            name: "exactly at floor",
            version: floor,
            expectedSupported: true
        ),
        Case(
            name: "same major/minor, patch above floor",
            version: OperatingSystemVersion(majorVersion: floor.majorVersion, minorVersion: floor.minorVersion, patchVersion: floor.patchVersion + 1),
            expectedSupported: true
        ),
        Case(
            name: "major version above floor",
            version: OperatingSystemVersion(majorVersion: floor.majorVersion + 1, minorVersion: 0, patchVersion: 0),
            expectedSupported: true
        ),
        Case(
            name: "major version well above floor, minor/patch zero",
            version: OperatingSystemVersion(majorVersion: floor.majorVersion + 5, minorVersion: 0, patchVersion: 0),
            expectedSupported: true
        )
    ]

    func test_isEmbeddedCeremonySupported_acrossTheFloorBoundary() {
        for testCase in cases {
            XCTAssertEqual(
                SEAWebAuthnCapability.isEmbeddedCeremonySupported(osVersion: testCase.version),
                testCase.expectedSupported,
                testCase.name
            )
        }
    }

    // MARK: - Explicit, unambiguous boundary cases (independent of the
    // current floor's own minor/patch values, unlike the table above)

    func test_belowFloor_isNotSupported() {
        let version = OperatingSystemVersion(majorVersion: 15, minorVersion: 9, patchVersion: 9)
        XCTAssertFalse(SEAWebAuthnCapability.isEmbeddedCeremonySupported(osVersion: version))
    }

    func test_atFloor_isSupported() {
        let version = OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        XCTAssertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(osVersion: version))
    }

    func test_aboveFloor_isSupported() {
        let version = OperatingSystemVersion(majorVersion: 18, minorVersion: 5, patchVersion: 0)
        XCTAssertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported(osVersion: version))
    }

    func test_defaultOsVersion_usesTheRealRunningOS() {
        // No injected version: exercises the default-parameter path against
        // whatever OS actually runs this test (a modern Simulator/device),
        // which today is always above the provisional iOS 16.0 floor.
        XCTAssertTrue(SEAWebAuthnCapability.isEmbeddedCeremonySupported())
    }

    // MARK: - isVersion(_:atLeast:) directly

    func test_isVersion_majorVersionDominates() {
        let higherMajor = OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0)
        let lowerMajorHigherMinor = OperatingSystemVersion(majorVersion: 16, minorVersion: 99, patchVersion: 99)
        XCTAssertTrue(SEAWebAuthnCapability.isVersion(higherMajor, atLeast: lowerMajorHigherMinor))
        XCTAssertFalse(SEAWebAuthnCapability.isVersion(lowerMajorHigherMinor, atLeast: higherMajor))
    }

    func test_isVersion_minorVersionDominatesWhenMajorEqual() {
        let higherMinor = OperatingSystemVersion(majorVersion: 16, minorVersion: 2, patchVersion: 0)
        let lowerMinorHigherPatch = OperatingSystemVersion(majorVersion: 16, minorVersion: 1, patchVersion: 99)
        XCTAssertTrue(SEAWebAuthnCapability.isVersion(higherMinor, atLeast: lowerMinorHigherPatch))
        XCTAssertFalse(SEAWebAuthnCapability.isVersion(lowerMinorHigherPatch, atLeast: higherMinor))
    }

    func test_isVersion_patchVersionCompared_whenMajorAndMinorEqual() {
        let higherPatch = OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 3)
        let lowerPatch = OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 2)
        XCTAssertTrue(SEAWebAuthnCapability.isVersion(higherPatch, atLeast: lowerPatch))
        XCTAssertFalse(SEAWebAuthnCapability.isVersion(lowerPatch, atLeast: higherPatch))
    }

    func test_isVersion_exactlyEqual_isAtLeast() {
        let version = OperatingSystemVersion(majorVersion: 16, minorVersion: 4, patchVersion: 1)
        XCTAssertTrue(SEAWebAuthnCapability.isVersion(version, atLeast: version))
    }
}
