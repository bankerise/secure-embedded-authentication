# SEA Core iOS — API Contract v1 (Phase 1)

Normative contract for `sea-core-ios`. Both the core implementation and `demo-ios`
build against exactly this surface. Any deviation is a contract break.

Scope of Phase 1 (this document):
- §6.2 authorize-URL integrity validation
- §6.3 callback capture
- §7.3 navigation policy
- §8.1/§8.2 hardened WKWebView surface
- §17.1 iOS screen-security posture
- §18.1 sheet presentation + appearance
- §20.1 telemetry event emission

**Explicitly out of scope for Phase 1:** JS bridge (§14), broker EXTERNAL_TAB
(§12.4), kill-switch fallback via ASWebAuthenticationSession (§21). Where the
spec requires these, leave a documented seam — never a stub that silently
succeeds. Passkeys / WebAuthn (§10) are now implemented — the WebAuthn
ceremony runs inside the hardened `WKWebView` surface with no separate Swift
API (no contract change), and the §10.4 capability fallback is implemented
as `SEAWebAuthnCapability` / `SEAFallbackAuthRunner` inside `SEASession`'s
internal view-controller selection. The same fallback runner is also
reachable directly via `SEAConfig.authMode = .nativeBrowser` — an explicit
caller choice to skip the embedded path entirely, independent of the
capability probe (see §3.1). App Attest (§16) and TLS pinning (§15)
are **not** SEA phase-2 work at all — they are host-app/API Gateway
responsibilities, out of this contract's scope entirely.

---

## 1. Module

Swift package `SEACore`, product `SEACore` (static library).
Platform floor: iOS 15.0. Swift 5.9+ tools. Zero third-party dependencies.
No React Native, no Objective-C bridging headers.

---

## 2. Threading (§4.7 — normative)

All public API is **main-thread-only**. All callbacks are delivered on the main
thread. Every public entry point begins with `SEAThread.assertMain()`, which is
`assertionFailure` in debug and a no-op in release.

---

## 3. Types

### 3.1 `SEAConfig`

```swift
public struct SEAConfig {
    public let authorizeURL: URL          // gateway-issued (§6.1)
    public let allowedDomains: [String]   // narrowing only (§7.1)
    public let presentation: SEAPresentation
    public let appearance: SEAAppearance
    public let timeoutMs: Int             // default 120_000
}

public enum SEAPresentation { case sheet, fullscreen }   // sheet is default
```

Init is memberwise-public with defaults for `presentation` (.sheet),
`appearance` (.default), `timeoutMs` (120_000), `allowedDomains` ([]).

Note: `capturePolicy` (§8) and `authMode` (§10.4) are not enumerated in the
code block above but are part of the type — both are additive fields with
defaults, so they don't change the shape callers must supply.

```swift
public enum SEAAuthMode { case embedded, nativeBrowser }   // embedded is default
```

`authMode = .nativeBrowser` skips the embedded `WKWebView` path entirely and
hands the whole login attempt to `ASWebAuthenticationSession` up front — the
same runner the §10.4 capability-probe fallback uses, entered explicitly
instead. Resolves through the exact same `SEASession.Callbacks` contract as
`.embedded`; not to be confused with the host-SDK-level `SYSTEM_BROWSER`
authMode (spec §6), which bypasses SEACore entirely.

Note: `SEAConfig` does **not** carry a `callbackScheme`. The callback scheme
is a single app-wide value owned by `SEAEnvironment` (§3.3) — it is not
something a per-session caller can vary, so it is not part of this
per-session config type.

### 3.2 `SEAAppearance` (§18.1 — colors & text only)

```swift
public struct SEAAppearance {
    public var headerBackground: UIColor
    public var headerText: UIColor
    public var accent: UIColor
    public var closeIconTint: UIColor
    public var cornerRadius: CGFloat
    public var title: String?              // nil → live page title (§18.1)
    public var showsGrabber: Bool
    public static let `default`: SEAAppearance
}
```

No layout injection. Appearance never touches web content (§13).

### 3.3 `SEAEnvironment` — host-app-supplied security config (§7.1, §6.2)

```swift
public struct SEAEnvironment {
    public let authDomains: Set<String>       // loaded from the host app's bundle
    public let callbackScheme: String         // loaded from the host app's bundle
    public static let current: SEAEnvironment // resolved once, on first access
}
```

The JS/host-supplied `allowedDomains` is **intersected** with `authDomains`.
Host input can narrow, never widen. An empty host list means "use the loaded
set unchanged". A host list disjoint from the loaded set yields an empty
effective allowlist → every navigation is denied (fail closed, not fail open).

SEACore is a single shared binary embedded by many different bank apps, each
with its own callback URL scheme and auth-domain allowlist. Those values are
**not compiled into SEACore** (that would require a different SEACore build
per integrating app). Instead, `SEAEnvironment.current` loads them at
runtime, once, from a dedicated `SEASecurityConfig.plist` bundled into the
**host application's own target** — read from `Bundle.main` (the app that
embeds SEACore), never from SEACore's own SPM resource bundle. This keeps
the callback scheme / domain allowlist just as native-trusted and
untouchable from JS/React Native as a compiled value would have been, while
letting one SEACore binary correctly serve many different apps: each
integrating app ships its own plist at *application*-packaging time, not at
SEACore's own *library*-build time. A dev/staging/prod split, if a given
integrating app wants one, is achieved by that app swapping which plist file
its build configuration/target includes — entirely outside SEACore's
concern; SEACore itself has no compile-time environment-flavor concept.

#### `SEASecurityConfig.plist` schema

A flat two-key dictionary, bundled as a resource in the **host app's own
target** (e.g. `apps/demo-ios/Sources/SEASecurityConfig.plist` for the demo
harness — never inside `sea-core-ios` itself):

```xml
<key>CallbackScheme</key>
<string>bkrmob</string>
<key>AuthDomains</key>
<array>
    <string>keycloak.example.com</string>
</array>
```

| Key | Type | Notes |
|---|---|---|
| `CallbackScheme` | `String` | The app's single registered custom URL scheme (one `CFBundleURLTypes` entry). Must be non-empty. |
| `AuthDomains` | `Array<String>` | The allowlist §7.1 narrows against. Must be non-empty. |

**Fail closed.** Any problem loading or parsing the plist — missing file,
unreadable, malformed dictionary, missing/wrong-typed `CallbackScheme`,
missing/empty `AuthDomains` — resolves `SEAEnvironment.current` to
`SEAEnvironment(authDomains: [], callbackScheme: "")`. An empty
`authDomains` means `effectiveAllowlist` can never contain anything (every
host check fails); an empty-string `callbackScheme` can never equal a real
URL's `.scheme`, so callback capture can never trigger either — this
mirrors the "any ambiguity resolves to failure" principle used throughout
the validator/policy. The failure path also raises `assertionFailure`, a
loud DEBUG-time signal to the integrating developer that their bundle is
missing or misconfigured; it is a no-op in Release, so a shipped app never
crashes over this.

### 3.4 `SEACallbackParams` (§6.3)

```swift
public struct SEACallbackParams {
    public let raw: [String: String]   // ALL query params, verbatim
    public var code: String? { raw["code"] }
    public var state: String? { raw["state"] }
    public var sessionState: String? { raw["session_state"] }
    public var error: String? { raw["error"] }
    public var errorDescription: String? { raw["error_description"] }
}
```

SEA performs **no** semantic validation of these (§6.3). Error-shaped callbacks
are delivered through `onCaptured`, not `onError`.

### 3.5 `SEAError` (§7.2)

```swift
public enum SEAError: Error, Equatable {
    case network(underlying: String)
    case timeout
    case cancelled
    case invalidAuthorizeURL(reason: SEAInvalidURLReason)
    case serverError(statusCode: Int)
    case webauthnUnavailable      // Phase 2 — declared, never thrown in Phase 1
    case killSwitched             // Phase 2 — declared, never thrown in Phase 1
}

public enum SEAInvalidURLReason: String {
    case scheme, host, userinfo, port, length, malformed
}
```

### 3.6 `SEAEvent` (§20.1)

```swift
public struct SEAEvent {
    public let name: String            // e.g. "AUTH_WEBVIEW_OPENED"
    public let properties: [String: String]
    public let timestamp: Date
}

public protocol SEATelemetrySink: AnyObject {
    func record(_ event: SEAEvent)     // called on main thread
}
```

Phase-1 event names emitted: `AUTH_WEBVIEW_OPENED`, `AUTH_PAGE_LOADED`,
`AUTH_NAV_BLOCKED`, `AUTH_COMPLETED`, `AUTH_CANCELLED`, `AUTH_FAILED`,
`AUTH_TIMEOUT`, `AUTH_CAPTURE_DETECTED`, `AUTH_LOGOUT_COMPLETED`.

**§20.2 data rules are normative and CI-tested:** never record usernames,
passwords, tokens, codes, cookies, or full URLs with query strings. Hostnames
are SHA-256 hashed and truncated to 16 hex chars (`host_hash`). Paths are
recorded only as a `page_class` bucket.

---

## 4. `SEASession` — entry point

```swift
public final class SEASession {
    public struct Callbacks {
        public var onCaptured: (SEACallbackParams) -> Void
        public var onCancelled: () -> Void
        public var onError: (SEAError) -> Void
    }

    public static weak var telemetrySink: SEATelemetrySink?

    /// Validates config (§6.2) and returns a presentable view controller.
    /// Throws SEAError.invalidAuthorizeURL before anything is loaded.
    public static func makeViewController(
        config: SEAConfig,
        callbacks: Callbacks
    ) throws -> UIViewController

    /// Convenience: validate, build, and present from `presenter`.
    @discardableResult
    public static func start(
        config: SEAConfig,
        from presenter: UIViewController,
        callbacks: Callbacks
    ) -> UIViewController?    // nil if validation failed → onError already fired

    /// §11.3 steps 2 (datastore purge). Steps 1/3/4 belong to the host SDK.
    public static func purgeWebData(completion: @escaping () -> Void)
}
```

Exactly one terminal callback fires per session (`onCaptured` XOR `onCancelled`
XOR `onError`). After a terminal callback the view controller dismisses itself
and all further callbacks are suppressed. This is invariant-tested.

---

## 5. Authorize-URL validation (§6.2 — normative)

`SEAAuthorizeURLValidator.validate(_ url: URL, against env: SEAEnvironment,
narrowedBy hostAllowlist: [String]) -> Result<URL, SEAInvalidURLReason>`

Rules, evaluated in order, all must pass:
1. `scheme == "https"` (case-insensitive) → else `.scheme`
2. no `user` and no `password` component → else `.userinfo`
3. `port` is nil or 443 → else `.port`
4. `absoluteString.utf8.count <= 2048` → else `.length`
5. host is non-nil, lowercased, and a member of the **effective allowlist**
   → else `.host`

Host matching is **exact, case-insensitive, ASCII-lowercased**. No suffix
matching — `evil-auth.bank.com` must not match `auth.bank.com`, and
`auth.bank.com.evil.io` must not match. IDN/punycode hosts compare on the
punycode form. A trailing dot in the host is stripped before comparison.

---

## 6. Navigation policy (§7.3 — normative)

Evaluated in `WKNavigationDelegate.decidePolicyFor` in this exact order:

1. **Callback-scheme match preempts everything.** If `url.scheme` equals
   `callbackScheme` (case-insensitive): cancel the navigation, extract all
   query params, fire `onCaptured`, emit `AUTH_COMPLETED`. Never allowed to
   proceed, never dispatched to the OS.
2. `about:blank` for the initial frame: allow.
3. `scheme == "https"` AND host ∈ effective allowlist AND
   (main frame OR same-origin subresource): allow.
4. Everything else: cancel, emit `AUTH_NAV_BLOCKED { scheme, host_hash }`.

Explicitly blocked schemes: `http`, `file`, `content`, `intent`, `javascript`,
`data`, `tel`, `mailto`, and any custom scheme other than `callbackScheme`.

`WKUIDelegate.createWebViewWith`: if the target URL is allowlisted, load it in
the same WebView and return nil; otherwise block. Never open externally.

Downloads: `WKDownloadDelegate` denies all.

**POST-redirect backstop (§6.3):** the callback URL is *also* checked in
`didCommit` and in the `webView.url` KVO observer. Capture is idempotent —
a guard flag ensures `onCaptured` fires at most once.

---

## 7. WKWebView configuration (§8.2 — normative)

- `websiteDataStore = .default()` (persistent, Safari-isolated)
- `limitsNavigationsToAppBoundDomains = true`
- `preferences.javaScriptCanOpenWindowsAutomatically = false`
- `defaultWebpagePreferences.allowsContentJavaScript = true` (Keycloak needs it)
- **zero** `WKUserScript`s, **zero** `WKScriptMessageHandler`s
- **no** `evaluateJavaScript` call anywhere in the package (CI-asserted, §24)
- media capture permission requests: denied via
  `webView(_:requestMediaCapturePermissionFor:...)` → `.deny`
- `didReceive challenge`: default system handling only. **Never** trust an
  invalid certificate; no debug bypass. (TLS pinning, if a deployment wants
  it, is applied by the host app's own networking client — out of
  `sea-core-ios` scope entirely, §15.)
- `didFailProvisionalNavigation` / `didFail` → `SEAError.network`, retry UI

Info.plist requirement for consumers, documented in the package README:
`WKAppBoundDomains` must list the auth domains.

---

## 8. Screen security (§17.1)

- On `willResignActive`: install an opaque branded cover view over the surface.
  Remove on `didBecomeActive`.
- Observe `UIScreen.main.isCaptured` (+ `capturedDidChangeNotification`) →
  emit `AUTH_CAPTURE_DETECTED { kind: "recording" }`.
- Observe `userDidTakeScreenshotNotification` → emit
  `AUTH_CAPTURE_DETECTED { kind: "screenshot" }`.
- Policy for recording is `SEACapturePolicy { .log, .warn, .blockInput }`,
  default `.warn`. Exposed on `SEAConfig` as `capturePolicy`.

---

## 9. UX (§18)

- Sheet: `UISheetPresentationController`, `.large()` detent, grabber per
  appearance, `cornerRadius` from appearance.
- Native header: back (visible only when `webView.canGoBack`), title, close.
  Title = `appearance.title` ?? live `webView.title`, sanitized to a single
  line, max 64 chars, never interpreted as markup.
- Swipe-to-dismiss = `onCancelled`; disabled while a navigation is in flight
  (`isModalInPresentation = true` during load).
- Loading: branded spinner until first `didFinish`.
- Failure surfaces are **native**, not web: offline / TLS / timeout / 5xx,
  each with a Retry action. Localized copy in en, fr, ar (RTL correct).

---

## 10. Test requirements

The package ships an `SEACoreTests` target covering, at minimum:
- Validator: every `SEAInvalidURLReason` path, plus the look-alike host corpus
  (`evil-auth.bank.com`, `auth.bank.com.evil.io`, `AUTH.BANK.COM`,
  `auth.bank.com.`, userinfo `https://auth.bank.com@evil.io/`, punycode).
- Allowlist intersection: narrowing works, widening is impossible, disjoint
  input fails closed.
- Navigation policy decision table across the blocked-scheme corpus.
- Callback capture: params extracted verbatim including duplicate and
  empty-valued keys; error-shaped callbacks routed to `onCaptured`.
- Terminal-callback-fires-exactly-once invariant.
- Telemetry redaction: no event property ever contains a raw host, a full URL,
  or a value from the callback query string.
