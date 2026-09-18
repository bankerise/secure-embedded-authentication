# SEA Core: iOS vs Android Parity Report

## Executive Summary

The Android implementation now covers **17 of 19 iOS source files** at the logic level, with full WebAuthn fallback functionality (§10.4) implemented. All critical issues have been resolved.

---

## File-by-File Comparison

### ✅ Parity Achieved (Core Logic)

| Module | iOS | Android | Notes |
|--------|-----|---------|-------|
| **AuthorizeURLValidator** | `SEAAuthorizeURLValidator.swift` | `SEAAuthorizeURLValidator.kt` | ✅ Fixed — all return statements uncommented |
| **NavigationPolicy** | `SEANavigationPolicy.swift` | `SEANavigationPolicy.kt` | ✅ Identical logic |
| **CallbackParams** | `SEACallbackParams.swift` | `SEACallbackParams.kt` | ✅ Identical logic |
| **Config** | `SEAConfig.swift` | `SEAConfig.kt` | ⚠️ Android adds `callbackScheme` field |
| **Environment** | `SEAEnvironment.swift` | `SEAEnvironment.kt` | ⚠️ Different loading strategy |
| **Error** | `SEAError.swift` | `SEAError.kt` | ✅ Identical taxonomy |
| **Event** | `SEAEvent.swift` | `SEAEvent.kt` | ✅ Identical structure |
| **TerminalGuard** | `SEATerminalGuard.swift` | `SEATerminalGuard.kt` | ✅ Identical logic |
| **Thread** | `SEAThread.swift` | `SEAThread.kt` | ✅ Identical logic |
| **Telemetry** | `SEATelemetry.swift` | `SEATelemetry.kt` | ✅ Identical logic |
| **WebViewFactory** | `SEAWebViewFactory.swift` | `SEAWebViewFactory.kt` | ⚠️ Platform-specific settings |
| **Appearance** | `SEAAppearance.swift` | `SEAAppearance.kt` | ⚠️ Android adds `sheetTopOffset` |
| **TitleSanitizer** | In `SEAAuthViewController.swift` | `SEATitleSanitizer.kt` | ✅ Identical logic (different file structure) |
| **Strings** | `SEAStrings.swift` | `SEAStrings.kt` | ✅ Identical logic |
| **FallbackAuthRunner** | `SEAFallbackAuthRunner.swift` | `SEAFallbackAuthRunner.kt` | ✅ Implemented (browser-based fallback) |
| **WebAuthnCapability** | `SEAWebAuthnCapability.swift` | `SEAWebAuthnCapability.kt` | ✅ Implemented (API level check) |
| **WebAuthnLiveFailure** | `SEAWebAuthnLiveFailure.swift` | `SEAWebAuthnLiveFailure.kt` | ✅ Implemented (identical logic) |

### ⚠️ Different Architecture (Android-specific)

| Module | Android File | Purpose | Spec Ref |
|--------|--------------|---------|----------|
| **AuthActivity** | `SEAAuthActivity.kt` | Activity-based auth surface | §9.1 |
| **AuthDelegate** | `SEAAuthDelegate.kt` | Shared WebView/terminal logic | §9.1 |
| **AuthFragment** | `SEAAuthFragment.kt` | Fragment for RN host Activities | §4.1 |

---

## Resolved Issues

### 1. `SEAAuthorizeURLValidator.kt` — Fixed

**File:** `packages/sea-core-android/src/main/java/com/bankerise/sea/core/SEAAuthorizeURLValidator.kt`

All return statements have been uncommented. The URL validator now properly validates:
- Scheme must be `https`
- No userinfo allowed
- Port must be -1 (unset) or 443
- URL length must be ≤ 2048 bytes
- Host must be in the effective allowlist

### 2. Environment Loading Strategy Difference

| Aspect | iOS | Android |
|--------|-----|---------|
| **Source** | `SEASecurityConfig.plist` (runtime) | `BuildConfig` (compile-time) |
| **Flexibility** | Host app bundles plist per environment | Requires rebuild per environment |
| **Fail-closed** | ✅ Empty domains on malformed plist | ⚠️ No runtime validation |
| **Security** | Plist is signed with app bundle | BuildConfig is in code |

**Impact:** Android's compile-time approach is less flexible but still secure. The iOS approach allows runtime configuration changes without app rebuild.

### 3. Screen Security — Missing Screenshot/Recording Detection

| Feature | iOS | Android |
|---------|-----|---------|
| **Task-switcher cover** | ✅ `willResignActive` cover view | ⚠️ `FLAG_SECURE` only |
| **Screen recording detection** | ✅ `UIScreen.capturedDidChangeNotification` | ❌ Not implemented |
| **Screenshot detection** | ✅ `userDidTakeScreenshotNotification` | ❌ Not implemented |
| **Capture policy overlay** | ✅ Full implementation | ❌ Not implemented |

**Impact:** Android relies solely on `FLAG_SECURE` which blocks screenshots/recordings but doesn't detect them. The capture policy (`LOG`, `WARN`, `BLOCK_INPUT`) is defined but not fully enforced.

### 4. WebAuthn Fallback (§10.4) — Not Implemented

The entire WebAuthn fallback path is missing in Android:

- **Pre-flight check** (`SEAWebAuthnCapability`): No OS version check for embedded ceremony support
- **Runtime fallback** (`SEAFallbackAuthRunner`): No `ASWebAuthenticationSession` equivalent
- **Live failure detection** (`SEAWebAuthnLiveFailure`): No Keycloak error redirect parsing

**Impact:** If the embedded WebView WebAuthn ceremony fails on Android, there is no automatic fallback path. Users would be stuck with a failed ceremony.

### 5. SEAConfig — `callbackScheme` Location

| Aspect | iOS | Android |
|--------|-----|---------|
| **Location** | `SEAEnvironment.callbackScheme` | `SEAConfig.callbackScheme` |
| **Source** | Loaded from plist | Passed by caller |
| **Overridable** | No (environment is immutable) | Yes (per-session) |

**Impact:** Android allows per-session callback scheme override, which is more flexible but differs from iOS's immutable environment-based approach.

---

## Test Coverage Comparison

### iOS Tests (15 files)

| Test File | Android Equivalent |
|-----------|-------------------|
| `SEAAuthorizeURLValidatorTests.swift` | `SEAAuthorizeURLValidatorTest.kt` ✅ |
| `SEAAuthViewControllerTests.swift` | ❌ Missing (different architecture) |
| `SEACallbackParamsTests.swift` | `SEACallbackParamsTest.kt` ✅ |
| `SEAConfigTests.swift` | `SEAConfigTests.kt` ✅ |
| `SEAEnvironmentAllowlistTests.swift` | `SEAEnvironmentAllowlistTest.kt` ✅ |
| `SEAEnvironmentLoadingTests.swift` | ❌ Missing (different loading strategy) |
| `SEAFallbackAuthRunnerTests.swift` | `SEAFallbackAuthRunnerTest.kt` ✅ |
| `SEANavigationPolicyTests.swift` | `SEANavigationPolicyTest.kt` ✅ |
| `SEAScreenSecurityTests.swift` | `SEAScreenSecurityTests.kt` ✅ |
| `SEASessionFallbackWiringTests.swift` | ❌ Missing (architecture differs) |
| `SEATelemetryTests.swift` | `SEATelemetryTest.kt` ✅ |
| `SEATerminalGuardTests.swift` | `SEATerminalGuardTest.kt` ✅ |
| `SEATitleSanitizerTests.swift` | `SEATitleSanitizerTest.kt` ✅ |
| `SEAWebAuthnCapabilityTests.swift` | `SEAWebAuthnCapabilityTest.kt` ✅ |
| `SEAWebAuthnLiveFailureTests.swift` | `SEAWebAuthnLiveFailureTest.kt` ✅ |

**Coverage:** 12/15 iOS test files have Android equivalents (80%)

---

## String Resource Differences

All string resources have been updated to match iOS content. Localized versions (fr, ar) now use the same user-friendly text as iOS.

---

## Resolved Issues

### 1. ✅ `SEAAuthorizeURLValidator.kt` — Fixed
All return statements uncommented. URL validator now properly validates scheme, userinfo, port, length, and host.

### 2. ✅ WebAuthn Fallback (§10.4) — Implemented
- `SEAWebAuthnCapability.kt`: Pre-flight API level check (min 26)
- `SEAWebAuthnLiveFailure.kt`: Live failure detection via Keycloak error redirect parsing
- `SEAFallbackAuthRunner.kt`: Browser-based fallback using external Intent

### 3. ✅ Screen Recording Detection — Implemented
- Added `startCaptureMonitoring()`/`stopCaptureMonitoring()` for API 30+
- Added `installCaptureOverlay()`/`removeCaptureOverlay()` for capture policy
- Updated `SEAAuthDelegate` to wire capture monitoring

### 4. ✅ Test Coverage — Improved
Added missing tests for WebAuthn capability, live failure detection, and fallback runner.

### 5. ✅ String Resources — Standardized
Updated all localized strings to match iOS content.

---

## Remaining Platform Differences (By Design)

### 1. Environment Loading Strategy
- **iOS:** Runtime plist loading (`SEASecurityConfig.plist`)
- **Android:** Compile-time `BuildConfig` fields

Android's approach requires rebuild per environment but is still secure. This is a deliberate architectural difference.

### 2. `callbackScheme` Location
- **iOS:** `SEAEnvironment.callbackScheme` (immutable)
- **Android:** `SEAConfig.callbackScheme` (per-session override)

Android allows more flexibility with per-session callback scheme.

### 3. Auth Surface Architecture
- **iOS:** Single `UIViewController` (`SEAAuthViewController`)
- **Android:** `SEAAuthActivity` + `SEAAuthDelegate` + `SEAAuthFragment`

Android uses Activity/Fragment pattern for better integration with Android lifecycle.

---

## Spec Compliance Summary

| Spec Section | iOS | Android | Notes |
|--------------|-----|---------|-------|
| §3.1 Config | ✅ | ✅ | Android adds `callbackScheme` |
| §3.3 Environment | ✅ | ✅ | Different loading strategy (by design) |
| §4 Entry Point | ✅ | ✅ | Different architecture (by design) |
| §5 URL Validation | ✅ | ✅ | Fixed — all validators active |
| §6 Navigation Policy | ✅ | ✅ | Identical logic |
| §7 WebView Hardening | ✅ | ✅ | Platform-specific settings |
| §8 Screen Security | ✅ | ✅ | Capture monitoring implemented |
| §9 Auth Surface | ✅ | ✅ | Different implementation |
| §10 WebAuthn | ✅ | ✅ | Fallback path implemented |
| §10.4 Fallback | ✅ | ✅ | All 3 components implemented |
| §11 Data Purge | ✅ | ✅ | Different APIs |
| §18 Presentation | ✅ | ✅ | Different UI framework |
| §20 Telemetry | ✅ | ✅ | Identical logic |

---

## Parity Score

**Before:** 14/19 files (74%) with 3 critical gaps
**After:** 17/19 files (89%) with full WebAuthn fallback and screen security

The remaining 2 files (`SEAAuthViewController.swift` equivalents) use different architecture by design (Activity/Fragment vs ViewController).
