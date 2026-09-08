# SEA React Native — API Contract v1

Normative technical specification for `sea-react-native` (npm package
`@bankerise-platform/sea-react-native`), the Fabric bridge wrapping
`sea-core-ios` and `sea-core-android`. `demo-rn` builds against exactly this
surface. Any deviation is a contract break.

Scope of this document: the JS-facing API, the native-component prop
contract, the platform bridge presenters, the security model, telemetry,
error taxonomy, the bottom-sheet/fullscreen presentation UI, and the build
and publish pipeline.

**Explicitly out of scope:** `sea-core-ios`/`sea-core-android`'s own
internal security logic (URL validation, navigation policy, screen
security) — see `docs/api-contract-ios-v1.md` and each core package's own
source for that. This document covers only the bridge layer: what crosses
from JS into native, and what the bridge itself does with it.

---

## 1. Module

npm package `@bankerise-platform/sea-react-native`, version `0.1.0` at time
of writing. React Native Fabric (new-architecture) component + one native
module (telemetry). Built with `react-native-builder-bob`
(`yarn prepare` → `bob build`) into `lib/module` (ESM) and
`lib/typescript` (`.d.ts`) — `main`/`types` in `package.json` point there,
never at `src/`. Peer dependencies: `react`, `react-native` (both `*`).

Design principle (core-first, bridge-thin): all authentication and
security logic lives in the native `sea-core-*` SDKs. This package is a
marshalling-only layer — it reads primitive prop values, hands them to a
platform-specific bridge presenter, and converts the result back to
primitives. No security-relevant decision logic lives here on either
platform.

---

## 2. Public JS API

### 2.1 `SecureAuthenticationView`

```ts
export type SecureAuthenticationViewProps = Readonly<{
  authorizeUrl: string;
  presentation?: 'sheet' | 'fullscreen';   // default 'sheet'
  authMode?: 'embedded' | 'nativeBrowser'; // default 'embedded'
  appearance?: SEAAppearance;
  onCaptured?: (params: Readonly<Record<string, string>>) => void;
  onCancelled?: () => void;
  onError?: (error: SEAError) => void;
}>;
```

A marshalling-only Fabric component. Mounting presents the hardened
embedded-WebView auth surface (or the WebAuthn-capability fallback) from
the underlying core; a terminal `onCaptured`/`onCancelled`/`onError` fires
exactly once, after which the host is expected to unmount the component —
unmounting dismisses whatever surface was presented.

Only per-session/UI values are props. Security knobs are **not** — see
§4.

`authMode = 'nativeBrowser'` skips the embedded path entirely and hands
the whole login attempt to the platform's system-browser runner
(`ASWebAuthenticationSession` on iOS, an external-browser Intent on
Android) up front — the same runner each core's own automatic
capability-probe fallback uses, just entered deliberately instead of
detected. Resolves through the exact same three callbacks either way.

### 2.2 `SEAAppearance`

```ts
export type SEAAppearance = Readonly<{
  headerBackground?: ColorValue;
  headerText?: ColorValue;
  accent?: ColorValue;
  closeIconTint?: ColorValue;
  cornerRadius?: number;
  title?: string;   // unused — see §5.3
}>;
```

Colors only, never layout. `title` is accepted for backward compatibility
but is currently unused on both platforms — no page title is ever
displayed in the header (§5.3).

### 2.3 `SEAError` / `SEAErrorCode`

```ts
export type SEAErrorCode =
  | 'network'
  | 'timeout'
  | 'cancelled'
  | 'invalid_authorize_url'
  | 'server_error'
  | 'webauthn_unavailable'
  | 'kill_switched';

export type SEAError = Readonly<{
  code: SEAErrorCode;
  message?: string;
}>;
```

Crosses the bridge unchanged from each core's own error taxonomy — see
§7.

### 2.4 Telemetry exports

```ts
export function subscribeToTelemetry(
  listener: (event: SEATelemetryEvent) => void
): () => void;

export function copyToClipboard(text: string): void;
export function purgeWebData(): Promise<void>;

export type SEATelemetryEvent = Readonly<{
  name: string;
  properties: Readonly<Record<string, string>>;
  timestampMs: number;
}>;
```

`subscribeToTelemetry` receives every event a core emits for as long as at
least one JS subscriber is active — subscribe once for the app's whole
lifetime (not just while a telemetry screen is mounted), since the native
emitter drops events fired while nothing is listening. All three no-op
(and `console.warn`) if the native `SeaTelemetryEmitter` module is
unavailable — e.g. an app launched from a build made before this module
was added, without a native rebuild since. `purgeWebData()` clears the
shared WebView datastore (cookies, cache, storage) — step 2 of the
four-step logout sequence; the other three steps (gateway session
invalidation, native token-jar cleanup, logout-completed telemetry) are
the host app's responsibility.

---

## 3. Native prop contract (codegen)

`SecureAuthenticationViewNativeComponent.ts` — the codegen source of
truth both platforms' native code must match:

```ts
export interface NativeProps extends ViewProps {
  authorizeUrl: string;
  presentation?: WithDefault<'sheet' | 'fullscreen', 'sheet'>;
  authMode?: WithDefault<'embedded' | 'nativeBrowser', 'embedded'>;
  appearance?: NativeAppearance;
  onCaptured?: DirectEventHandler<CapturedNativeEvent>;
  onCancelled?: DirectEventHandler<CancelledNativeEvent>;
  onError?: DirectEventHandler<ErrorNativeEvent>;
}
```

`onCaptured`'s native event carries a `paramsJson: string` — an arbitrary
`String:String` map crosses Fabric's strictly-typed event schema as a JSON
string, parsed back into a plain object by the JS wrapper before reaching
the public `onCaptured` callback. This is mechanical marshalling only, not
a semantic interpretation of the params — the bridge never inspects their
contents.

Any prop not listed here (e.g. `allowedDomains`, `timeoutMs`,
`callbackScheme`) is not part of the contract on either platform — see §4.

---

## 4. Security model — what is not a prop, and why

Security knobs (allowed domains, callback scheme, allowed URI schemes,
allowed ports, max URL length, session timeout) are deliberately **not**
props on `SecureAuthenticationView`. They are owned entirely by
native-platform config the host app bundles into its own signed target,
loaded by each core independently of anything JS supplies:

| Platform | Source file | Loaded by |
|---|---|---|
| iOS | `SEASecurityConfig.plist` | `SEAEnvironment.current` |
| Android | `bankerise-sea.properties` (in `assets/`) | `SEAPropertiesLoader` |

This keeps these values just as untouchable from JS as compiled constants
would be, without requiring either core to be recompiled per integrating
app. Any problem loading or parsing either file fails closed (empty
allowlist, empty callback scheme — every check then fails).

### 4.1 `AllowedSchemes` (both platforms)

Both config files support an optional `allowedSchemes`/`AllowedSchemes`
key (Android: comma-separated string, default `https`; iOS: plist string
array, default `["https"]`). Absent or empty on either platform falls
back to https-only. This exists specifically for local dev where a domain
is served over plain `http://` behind no TLS-terminating proxy — **never**
set for a production domain. iOS's validator previously had no override
mechanism at all here (hardcoded `scheme == "https"`); Android's `SEAConfig`
already supported `allowedSchemes` before iOS gained parity.

### 4.2 Android cleartext traffic (separate, OS-level control)

Independently of the above, Android's WebView enforces its own
OS-level cleartext-traffic policy via `AndroidManifest.xml`
(`usesCleartextTraffic`) or, more precisely, a Network Security Config XML
(`android:networkSecurityConfig`) with scoped `<domain-config
cleartextTrafficPermitted="true">` entries. Setting `allowedSchemes` in
`bankerise-sea.properties` alone is **not** sufficient to permit an
`http://` authorize URL to load — the host app's own manifest/network
security config must also explicitly permit cleartext for that domain, or
the WebView fails the navigation with `net::ERR_CLEARTEXT_NOT_PERMITTED`
regardless of what the core's own validator allows. These are two
independent gates; both must agree.

---

## 5. Platform bridge presenters

### 5.1 iOS — `SEABridgePresenter.swift` / `SeaReactNativeView.mm`

```swift
@objc public static func start(
    fromAnchor anchorView: UIView,
    authorizeUrl: String,
    presentation: String,
    authMode: String,
    headerBackground: UIColor?,
    headerText: UIColor?,
    accent: UIColor?,
    closeIconTint: UIColor?,
    cornerRadius: NSNumber?,
    title: String,
    callbacks: SEABridgeCallbacks
) -> UIViewController?
```

Marshals prop values into a `SEAConfig`, calls `SEASession.start`, marshals
the result back to primitives via `SEABridgeCallbacks`
(`onCaptured(String)`, `onCancelled()`, `onError(String, String?)`). No
authentication/navigation/validation logic lives here — that is entirely
`SEACore`'s.

### 5.2 Android — `SEABridgePresenter.kt` / `SeaReactNativeView.kt` /
`SeaReactNativeViewManager.kt`

```kotlin
fun start(
    activity: Activity,
    authorizeUrl: String,
    presentation: String,
    authMode: String,
    headerBackground: Int?,
    headerText: Int?,
    accent: Int?,
    closeIconTint: Int?,
    cornerRadius: Float?,
    title: String,
    callbacks: BridgeCallbacks
): Boolean
```

Loads the host app's `SEAConfig` via `SEAPropertiesLoader.loadConfig`,
then overrides only the per-session values (`authorizeUrl`,
`presentation`, `authMode`, `appearance`) before calling
`SEASession.start`. `authMode` support (both the bridge parameter and the
underlying `sea-core-android` `SEAConfig.authMode`/`SEAAuthMode` field
and `SEASession` routing) was added to reach parity with iOS — previously
Android had no way to honor an explicit `nativeBrowser` selection from
JS at all; it silently always used the automatic capability-probe
decision regardless of what the caller requested.

`SeaReactNativeViewManager` registers each prop via `@ReactProp` and
forwards it to `SeaReactNativeView`, which calls `SEABridgePresenter.start`
once both a non-empty `authorizeUrl` and an `Activity` are available
(mirrors iOS's `startIfNeeded` dual-hook — props and window attachment can
arrive in either order).

---

## 6. Presentation UI (Android specifics)

iOS's `sheet` presentation uses the system's native
`UISheetPresentationController` — swipe-to-dismiss, backdrop, and grabber
are all OS-provided; `fullscreen` uses a plain full-screen
`UIViewController` with an explicit header close button in both cases.
Android has no equivalent system component and builds its own bottom
sheet; the two platforms have deliberately diverged in how dismissal
works, per product decision:

| | iOS | Android |
|---|---|---|
| `sheet` dismiss | System swipe-to-dismiss, backdrop tap | Drag-down on header (toolbar/grabber), tap outside the sheet's bounds, system back — **no close button** |
| `fullscreen` dismiss | Header close button | Header close button (only presentation mode with one) |
| `sheet` backdrop | System-dimmed | None — fully transparent, host app visible behind |
| Header title text | Shown (live page title or configured `title`) | Never shown on either presentation — `titleTextView` stays in the layout only as a flexible spacer |

### 6.1 Android drag-to-dismiss

Implemented in `SEAAuthDelegate.attachDragToDismiss`, attached only to the
sheet's header (toolbar + grabber), never the WebView — so it can never
compete with the WebView's own touch/scroll handling. Downward drag
translates the sheet; on release, dismisses if the drag passed 35% of the
sheet's height *or* the release velocity passed 800dp/s, otherwise snaps
back.

### 6.2 Android fullscreen background & keyboard

`createView()` (fullscreen) sets its container's background from
`config.appearance.headerBackground` — mirrors iOS's
`view.backgroundColor = config.appearance.headerBackground`. Because this
app targets API 35+ (edge-to-edge enforced by default),
`windowSoftInputMode="adjustResize"` alone is no longer sufficient to keep
a focused WebView input field above the keyboard; `applyImeInsetPadding`
pads the WebView's container by the live `WindowInsetsCompat.Type.ime()`
inset instead, shrinking its rendered viewport so the WebView's own
scroll-into-view behavior can do the rest. Sheet mode does not (yet) have
this applied.

### 6.3 Android status bar

`SEAAuthActivity` is a real, separate Activity (`android:windowIsTranslucent`),
themed via `SEA.AuthSheetTheme`. Its `statusBarColor`/`navigationBarColor`
are explicitly transparent, so it never repaints the status bar with
`Theme.MaterialComponents.Light`'s own default — the host app's real
status bar just keeps showing through unchanged on both open and dismiss.
Status bar *icon* color (light/dark) is intentionally left untouched by
this theme, since forcing a fixed value could be wrong for a host app
using the opposite scheme.

### 6.4 Android first-navigation DNS retry

`SEAAuthDelegate`'s `WebViewClient.onReceivedError` retries once, silently,
on `WebViewClient.ERROR_HOST_LOOKUP` (`net::ERR_NAME_NOT_RESOLVED`) if it
occurs on the very first navigation — a known Android WebView cold-start
quirk (Chromium's network stack not yet initialized) unrelated to any
real DNS/connectivity problem, gone by the next attempt. A genuine
second failure surfaces normally. This is Android-only — iOS's `WKWebView`
does not exhibit this behavior and has no equivalent.

---

## 7. Error taxonomy

`SEAErrorCode` values map 1:1 to each core's own error cases:

| Code | Meaning |
|---|---|
| `network` | Underlying network failure (message carries the description) |
| `timeout` | Session exceeded `SEAConfig.timeoutMs` (default 120,000ms, native-config only) |
| `cancelled` | User dismissed without completing |
| `invalid_authorize_url` | Failed `SEAAuthorizeURLValidator` (message carries the specific reason: scheme, host, userinfo, port, length, malformed) |
| `server_error` | HTTP 5xx from the authorize URL's response |
| `webauthn_unavailable` | Embedded WebAuthn ceremony unsupported and fallback also failed |
| `kill_switched` | Remote-config kill switch engaged |

---

## 8. Telemetry event taxonomy

Event names emitted via `subscribeToTelemetry`, identical on both
platforms:

`AUTH_WEBVIEW_OPENED`, `AUTH_PAGE_LOADED`, `AUTH_NAV_BLOCKED`,
`AUTH_COMPLETED`, `AUTH_CANCELLED`, `AUTH_FAILED`, `AUTH_TIMEOUT`,
`AUTH_CAPTURE_DETECTED`, `AUTH_LOGOUT_COMPLETED`, `AUTH_WEBAUTHN_FALLBACK`.

`AUTH_WEBVIEW_OPENED` carries a `prewarmed` property, currently hardcoded
`"true"` for the embedded path and `"false"` for the fallback path on
both platforms — this is a descriptive label distinguishing embedded vs.
fallback mode, **not** a claim that any actual WebView engine
pre-warming happens; no such mechanism is implemented on either platform
today (see §6.4 for the specific consequence of that on Android).

No PII/credentials/tokens/cookies in any event; hostnames are hashed.

---

## 9. Build & publish

Build: `yarn prepare` → `bob build` (`react-native-builder-bob`), targets
`module` (ESM) and `typescript` (`.d.ts`), source `src/`, output `lib/`.

Publish: GitHub Actions (`.github/workflows/sea-react-native.yml`),
triggered on `sea-react-native/*.*.*` tags — part of this monorepo's
lockstep versioning (all three `sea-*` packages tagged and released
together; independent version drift is prohibited). The workflow syncs
the tag's version into `package.json`, builds, then publishes to the npm
registry as `@bankerise-platform/sea-react-native` (public access).
Toolchain: Yarn Classic 1.22.22 (pinned via Corepack) — this repo does not
use Yarn Berry.

---

## 10. Testing

`src/__tests__/index.test.tsx` — the only test file in this package
currently. No Android/iOS instrumented UI tests exist for the bridge or
the bottom-sheet presentation described in §6; that behavior has been
verified by manual review and code inspection only (see this package's
git history for the specific fixes), not by an automated test suite.
