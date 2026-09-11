# @bankerise-platform/sea-react-native

React Native Fabric bridge for **Bankerise SEA (Secure Embedded Authentication)** — a hardened, native, in-app WebView login surface for iOS and Android.

## What it is, and what problem it solves

Embedding an OAuth/OIDC login flow inside a mobile app the naive way — a plain WebView with no restrictions — opens the door to phishing via URL tampering, navigation to arbitrary/attacker-controlled domains, credential/session leakage through screenshots or screen recording, and callback interception. SEA solves this by presenting a **fully native, locked-down** auth surface instead of a generic WebView:

- Only an explicitly allowlisted set of domains can ever load
- The authorize URL is validated (scheme + host) before anything loads
- The OAuth callback is captured **in-process**, before it ever becomes a real outbound request
- Screenshots/recordings are detected and mitigated
- The host app can never touch the WebView's cookies, DOM, or JavaScript directly

`sea-react-native` is a **thin, marshalling-only bridge** — it contains no authentication, navigation, storage, crypto, or networking logic of its own. All of that lives in the native cores, [`sea-core-ios`](../sea-core-ios) (Swift) and [`sea-core-android`](../sea-core-android) (Kotlin); this package just exposes a `<SecureAuthenticationView>` Fabric component and a small telemetry API to React Native.

## Features

- Native, hardened embedded-WebView auth surface — **sheet** or **fullscreen** presentation
- Domain-allowlisted navigation with fail-closed origin validation
- In-process OAuth/OIDC callback capture — no OS-level redirect round-trip needed for the default flow
- Optional **native-browser fallback** (`ASWebAuthenticationSession` on iOS) for devices that can't run the embedded WebAuthn/passkey ceremony
- Screen-capture detection and mitigation; no persistent caching of session web data
- Configurable per-session UI — presentation, title, colors, sheet corner radius
- Strict terminal-callback contract: exactly one of `onCaptured` / `onCancelled` / `onError`, exactly once, per mount
- Built-in telemetry stream mirroring every internal SEA lifecycle event, plus a `purgeWebData()` helper for logout
- Zero external artifact host required for either native half — iOS resolves `SEACore` from this repo's own CocoaPods Specs index; Android ships `sea-core-android` as a prebuilt AAR bundled inside this very npm package

## Requirements & prerequisites

| | Requirement |
|---|---|
| React Native | **0.86+**, with the **New Architecture (Fabric) enabled**. This is a Fabric-only component (built with `codegenNativeComponent`) — it will not work under the legacy Paper renderer. |
| React | 19+ |
| Node | >= 22.13 |
| iOS | 15.0+ deployment target, Xcode with CocoaPods, Swift 5.9+ |
| Android | minSdk 24 (Android 7.0+), compileSdk 35+, Kotlin, JDK 17 |
| Other | An OAuth/OIDC authorize URL from your identity gateway, and a callback URL scheme registered with that gateway |

Installing the npm package alone is **not enough** — both native platforms need one project-level addition each, because Gradle and CocoaPods each scope dependency/repository resolution to the *consuming* project, not to the library that declares the dependency. The sections below walk through exactly what's needed.

## Installation

```sh
npm install @bankerise-platform/sea-react-native
# or
yarn add @bankerise-platform/sea-react-native
```

## Native Android configuration

Add the bundled `sea-core-android` AAR's local Maven repository to your app's **`android/build.gradle`**:

```groovy
allprojects {
    repositories {
        maven { url "$rootDir/../node_modules/@bankerise-platform/sea-react-native/android/local-maven" }
    }
}
```

That's the only Gradle change required — autolinking wires up the rest of the module. `sea-core-android`'s own `AndroidManifest.xml` is merged into your app automatically and already declares:

- the `INTERNET` and `DETECT_SCREEN_CAPTURE` permissions
- the `SEAAuthActivity` that hosts the auth surface

You do not need to add either of these yourself.

> **Known limitation — `authMode="nativeBrowser"` on Android only:** the OS-level redirect intent-filter used by the native-browser fallback path is currently fixed to the scheme `sea-default-callback` and is not yet app-configurable (unlike iOS, where the scheme comes from your own `Info.plist`). If you use `nativeBrowser`, your OAuth client's registered Android redirect URI must be `sea-default-callback://callback`, and the `callbackScheme` in `bankerise-sea.properties` (below) must match it exactly. The default `embedded` presentation is unaffected by this — it intercepts the callback inside the WebView itself and works with whatever scheme you configure.

## Native iOS configuration

Add this repository as a CocoaPods source in your **`Podfile`**, alongside the default CDN. `SEACore` — the native core `sea-react-native` depends on — is resolved from the CocoaPods Specs index committed inside this same repository, not a separate private host:

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/bankerise/secure-embedded-authentication.git'

pod 'SEACore', '~> 0.0.9'   # pin to the version this sea-react-native release was built against
```

Then:

```sh
cd ios && pod install
```

No `AppDelegate` changes are required. The native-browser fallback uses `ASWebAuthenticationSession`, which handles its callback internally — your app does not need to implement `application(_:open:options:)`.

## Required project-level configuration

This part is deliberately **not** shipped inside the library: the values below are security-sensitive and must come from your own signed app bundle, not from a binary shared across every app that embeds SEA. Skipping this step doesn't crash the app — it fails closed (see Troubleshooting).

### iOS — `SEASecurityConfig.plist`

Add a plist file named exactly `SEASecurityConfig.plist` to your Xcode project, included in your app target's **Copy Bundle Resources** build phase:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CallbackScheme</key>
    <string>yourapp</string>
    <key>AuthDomains</key>
    <array>
        <string>auth.yourbank.com</string>
    </array>
    <!-- Optional — omit entirely to keep the https-only default -->
    <key>AllowedSchemes</key>
    <array>
        <string>https</string>
    </array>
</dict>
</plist>
```

Also register `CallbackScheme`'s value as a URL scheme in `Info.plist`, so the OS can route the native-browser fallback's redirect back to your app:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>
        </array>
    </dict>
</array>
```

### Android — `bankerise-sea.properties`

Place a file at **`android/app/src/main/assets/bankerise-sea.properties`**:

```properties
callbackScheme=yourapp
authDomains=auth.yourbank.com
# Optional — omit entirely to keep the https-only default
allowedSchemes=https
```

### Schema, side by side

| Meaning | iOS key (`SEASecurityConfig.plist`) | Android key (`bankerise-sea.properties`) | Required? |
|---|---|---|---|
| Callback URL scheme | `CallbackScheme` (string) | `callbackScheme` | Yes |
| Allowed auth domains | `AuthDomains` (array) | `authDomains` (comma-separated) | Yes |
| Allowed URL schemes | `AllowedSchemes` (array) | `allowedSchemes` (comma-separated) | No — defaults to `https` only |

**Fail-closed behavior:** if either file is missing, unreadable, or missing `CallbackScheme`/`AuthDomains`, the library falls back to an empty domain allowlist and an empty callback scheme — every navigation is blocked and no callback can ever be captured. It fails closed, never open, and never crashes a release build.

**Not currently exposed anywhere** — neither as a prop nor a config-file key, fixed internal defaults only: session timeout (120s), maximum authorize-URL length, and the allowed port set. Changing any of these requires a native-code change, not a configuration one.

## React Native integration

```tsx
import { SecureAuthenticationView } from '@bankerise-platform/sea-react-native';

function LoginScreen({ authorizeUrl }: { authorizeUrl: string }) {
  const [showAuth, setShowAuth] = React.useState(true);
  if (!showAuth) return null;

  return (
    <SecureAuthenticationView
      authorizeUrl={authorizeUrl}
      presentation="sheet"
      onCaptured={(params) => {
        // Raw callback query params (e.g. { code, state }) — exchange them
        // with your own backend/gateway. sea-react-native never performs
        // the token exchange itself.
        setShowAuth(false);
        handleAuthorizationCode(params.code, params.state);
      }}
      onCancelled={() => setShowAuth(false)}
      onError={(error) => {
        setShowAuth(false);
        console.warn('SEA login failed:', error.code, error.message);
      }}
    />
  );
}
```

Unmounting the component dismisses the presented surface — mount it conditionally, as above, rather than always rendering it.

### With appearance customization

```tsx
<SecureAuthenticationView
  authorizeUrl={authorizeUrl}
  presentation="sheet"
  appearance={{
    title: 'Sign in',
    accent: '#1976D2',
    headerBackground: '#FFFFFF',
    headerText: '#212121',
    cornerRadius: 16,
  }}
  onCaptured={handleCaptured}
  onCancelled={handleCancelled}
  onError={handleError}
/>
```

### Native-browser fallback

```tsx
<SecureAuthenticationView
  authorizeUrl={authorizeUrl}
  authMode="nativeBrowser" // skips the embedded WebView; uses the system auth browser
  onCaptured={handleCaptured}
  onCancelled={handleCancelled}
  onError={handleError}
/>
```

### Telemetry and logout

```tsx
import { subscribeToTelemetry, purgeWebData } from '@bankerise-platform/sea-react-native';

React.useEffect(() => {
  return subscribeToTelemetry((event) => {
    console.log(event.name, event.properties, event.timestampMs);
  });
}, []);

async function logout() {
  await purgeWebData(); // clears the shared WebView cookie/data store
}
```

## How it works

1. You mount `<SecureAuthenticationView authorizeUrl={...} />`.
2. The bridge marshals your props into a native config and asks the native core to present the auth surface — a native sheet or fullscreen screen hosting a locked-down WebView.
3. The WebView loads `authorizeUrl` **only after** it passes validation against your `AuthDomains`/`AllowedSchemes`. Every subsequent navigation inside the WebView is checked the same way — anything off-allowlist is blocked outright, never silently redirected.
4. When a navigation's URL scheme matches your configured `callbackScheme`, the native core intercepts it **before** it becomes a real network request, extracts the query parameters, and fires `onCaptured` exactly once. The WebView is torn down immediately after.
5. If the user dismisses the surface first (swipe, back, close), `onCancelled` fires instead. Any native failure (network error, server 5xx, timeout, unsupported WebAuthn, invalid authorize URL) fires `onError` with a typed error code.
6. Exactly one of `onCaptured` / `onCancelled` / `onError` fires, exactly once, for the lifetime of a mounted component.
7. Token exchange, session storage, and everything past "here are the raw callback params" is entirely your app's responsibility — this library's job ends at capture.

`authMode="nativeBrowser"` replaces steps 2–4 with `ASWebAuthenticationSession` — used when a device can't run the embedded WebAuthn/passkey ceremony, or when you want the system-browser experience by default.

## API reference

### `<SecureAuthenticationView>` props

| Prop | Type | Default | Notes |
|---|---|---|---|
| `authorizeUrl` | `string` | — (required) | Must pass your native config's allowlist, or the surface will error rather than load |
| `presentation` | `'sheet' \| 'fullscreen'` | `'sheet'` | |
| `authMode` | `'embedded' \| 'nativeBrowser'` | `'embedded'` | See "How it works" and the Android known-limitation note above |
| `appearance` | `SEAAppearance` (below) | — | UI-only, per-session — never affects security behavior |
| `onCaptured` | `(params: Record<string, string>) => void` | — | Raw callback query params |
| `onCancelled` | `() => void` | — | User dismissed the surface |
| `onError` | `(error: SEAError) => void` | — | See error codes below |

### `SEAAppearance`

| Key | Type | Notes |
|---|---|---|
| `headerBackground` | color | |
| `headerText` | color | |
| `accent` | color | Spinner / retry-button tint |
| `closeIconTint` | color | |
| `cornerRadius` | `number` | Density-independent (dp on Android, pt on iOS) — the same value renders the same visual radius on both platforms |
| `title` | `string` | Omit to fall back to the live page `<title>` |

### `SEAError` / `SEAErrorCode`

| Code | Meaning |
|---|---|
| `network` | Underlying request failed (no connectivity, DNS, TLS, etc.) |
| `timeout` | Session exceeded its internal timeout (120s, fixed) |
| `cancelled` | Reserved — user dismissal is reported via `onCancelled`, not this code |
| `invalid_authorize_url` | `authorizeUrl` failed native validation (disallowed scheme/host) before anything loaded |
| `server_error` | The authorize page responded with an HTTP 5xx |
| `webauthn_unavailable` | Device can't run the embedded WebAuthn ceremony (embedded path only) |
| `kill_switched` | Reserved for a remote kill switch, if/when configured |

### Telemetry API

| Export | Signature | Notes |
|---|---|---|
| `subscribeToTelemetry` | `(listener: (event: SEATelemetryEvent) => void) => () => void` | Returns an unsubscribe function. Warns and no-ops if the native module isn't present in the running binary (stale build) |
| `purgeWebData` | `() => Promise<void>` | Clears the shared WebView cookie/data store — call on logout |
| `copyToClipboard` | `(text: string) => void` | Debug-harness convenience; not part of the auth flow itself |

## Troubleshooting

- **Login always cancels/fails immediately; the page never loads.** Your native security config file is almost certainly missing or invalid — the library fails closed silently in release builds. Add `SEASecurityConfig.plist` / `bankerise-sea.properties` per "Required project-level configuration" above, and check the console for a fail-closed warning in debug builds.
- **iOS build fails: `[!] CocoaPods could not find compatible versions for pod "SEACore"`.** You're missing the `source 'https://github.com/bankerise/secure-embedded-authentication.git'` line in your Podfile, or your version pin doesn't match anything published to the repo's `Specs/SEACore/` index.
- **Android build fails: `Could not find com.bankerise:sea-core-android:...`.** You're missing the `allprojects { repositories { maven {...} } }` addition in `android/build.gradle` (see Android configuration above) — Gradle scopes repository resolution to the project resolving the dependency, not the one declaring it, so the library can't add this for you automatically.
- **`authMode="nativeBrowser"` never returns to the app on Android.** Your OAuth client's redirect URI doesn't match the fixed `sea-default-callback://callback` scheme this path currently requires on Android — see the known-limitation note above.
- **`subscribeToTelemetry` / `purgeWebData` warn "native module is unavailable".** You installed or updated the npm package but haven't rebuilt the native app (`pod install` + a real Xcode/Gradle build) — a JS-only reload isn't enough to pick up native module changes.
- **Changing `appearance` while the surface is already open does nothing.** Appearance is read once at present-time; update it before mounting, not while it's already showing.

## Version compatibility

| | Minimum | Tested against |
|---|---|---|
| React Native | 0.86 (New Architecture/Fabric required) | 0.86.0 |
| React | 19 | 19.2.3 |
| Node | 22.13 | — |
| iOS | 15.0 | Xcode, Swift 5.9 |
| Android | API 24 (Android 7.0) | compileSdk 35, JDK 17 |

## What's handled internally vs. what you must configure

| | Handled by the library | You must configure |
|---|---|---|
| WebView hardening, navigation policy, screen-capture handling | ✅ | |
| Fabric bridge, event marshalling, telemetry plumbing | ✅ | |
| `sea-core-android` native dependency resolution | ✅ (bundled prebuilt AAR) | One Gradle repository line |
| `SEACore` (iOS) native dependency resolution | ✅ (Specs index hosted in this repo) | Podfile `source` line + version pin |
| Callback URL scheme, auth domain allowlist, allowed URL schemes | Enforced fail-closed | Supply `SEASecurityConfig.plist` / `bankerise-sea.properties` |
| Per-session UI (title, colors, corner radius, presentation) | Rendered as configured | Pass `appearance` / `presentation` props, or accept native defaults |
| Session timeout, allowed ports, max URL length | Fixed internal defaults | Not currently configurable |
| Token exchange, session storage, post-login navigation | Explicitly out of scope | Entirely your app's responsibility |

## License

MIT

---

Contributing to this package itself (not just consuming it)? See the monorepo's [infra/README.md](../../infra/README.md) and [CONTRIBUTING.md](../../CONTRIBUTING.md) for the local dev-mode setup, which differs from the flow above (local CocoaPods `:path` instead of the Specs index, Yarn workspaces instead of a published npm install).

Scaffolded with [create-react-native-library](https://github.com/callstack/react-native-builder-bob).
