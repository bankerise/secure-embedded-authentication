# iOS guide

Add SEA's secure login screen to a native iOS app (UIKit or SwiftUI).

**Requirements:** iOS 15.0+, Swift 5.9+, CocoaPods.

## 1. Install

SEA's CocoaPods spec index lives in this repository. Add it as a source next
to the default CDN in your `Podfile`:

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/bankerise/secure-embedded-authentication.git'

target 'MyApp' do
  pod 'SEACore', '~> 0.0.1'
end
```

Then run:

```bash
pod install
```

## 2. Configure

SEA reads its security settings from your app bundle, not from code, so they
can't be changed at runtime.

**a. Create `SEASecurityConfig.plist`** and add it to your app target
(Copy Bundle Resources):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- The scheme of your OAuth redirect URI, e.g. myapp://callback -->
    <key>CallbackScheme</key>
    <string>myapp</string>
    <!-- Domains the login WebView may load -->
    <key>AuthDomains</key>
    <array>
        <string>auth.example.com</string>
    </array>
</dict>
</plist>
```

**b. List the same domains as App-Bound Domains** in `Info.plist`. SEA turns
on WebKit's App-Bound Domains restriction:

```xml
<key>WKAppBoundDomains</key>
<array>
    <string>auth.example.com</string>
</array>
```

**c. Register the callback scheme** in `Info.plist`. It's used by the
system-browser fallback:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myapp</string>
        </array>
    </dict>
</array>
```

**d. (Passkeys) Add an Associated Domains entitlement** for your identity
provider's domain, and serve an `apple-app-site-association` file from it
that lists your app:

```
webcredentials:auth.example.com
```

> If the config file is missing or incomplete, SEA **fails closed**: every
> navigation is blocked and no callback can be captured. It never crashes.

## 3. Start a login

Get an authorize URL from your backend, then:

```swift
import SEACore

let config = SEAConfig(
    authorizeURL: authorizeURL,
    presentation: .sheet            // or .fullscreen
)

SEASession.start(
    config: config,
    from: self,                     // the presenting UIViewController
    callbacks: .init(
        onCaptured: { params in
            // params.code, params.state, params.raw…
            // Send them to your backend to exchange for tokens.
        },
        onCancelled: {
            // The user closed the login screen.
        },
        onError: { error in
            // See "Errors" below.
        }
    )
)
```

All SEA APIs must be called on the main thread, and all callbacks arrive on
the main thread.

**SwiftUI:** present from the top-most `UIViewController`, or use
`SEASession.makeViewController(config:callbacks:)` and wrap the result in a
`UIViewControllerRepresentable`.

## Customize the look

```swift
let appearance = SEAAppearance(
    headerBackground: .systemBackground,
    headerText: .label,
    accent: .systemBlue,
    closeIconTint: .secondaryLabel,
    cornerRadius: 16,
    title: "Sign in"                // nil shows the page's own title
)

let config = SEAConfig(authorizeURL: authorizeURL, appearance: appearance)
```

## Other options

| `SEAConfig` parameter | Default | What it does |
|---|---|---|
| `allowedDomains` | `[]` | Narrows `AuthDomains` for this session. It can only narrow, never add |
| `presentation` | `.sheet` | `.sheet` or `.fullscreen` |
| `timeoutMs` | `120_000` | Gives up with `.timeout` after this long |
| `capturePolicy` | `.warn` | What happens on screen capture: `.log`, `.warn` or `.blockInput` |
| `authMode` | `.embedded` | `.nativeBrowser` always uses `ASWebAuthenticationSession` instead of the WebView |

## Local development over `http`

SEA only loads `https` by default. If your local identity provider has no
TLS, you can allow plain `http` in **debug builds only**:

1. Add `http` to `AllowedSchemes` in `SEASecurityConfig.plist`:

   ```xml
   <key>AllowedSchemes</key>
   <array>
       <string>https</string>
       <string>http</string>
   </array>
   ```

2. Let the WebView load cleartext for that host with an App Transport
   Security exception in `Info.plist`. `NSAllowsLocalNetworking` covers
   `localhost`, `*.local` and bare IP addresses:

   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsLocalNetworking</key>
       <true/>
   </dict>
   ```

3. Keep the host in `AuthDomains` and `WKAppBoundDomains` as usual.

4. If your provider runs on a non-standard port, allow it with
   `AllowedPorts` in `SEASecurityConfig.plist` (the default is `443`; a URL
   with no explicit port is always accepted):

   ```xml
   <key>AllowedPorts</key>
   <array>
       <integer>443</integer>
       <integer>8080</integer>
   </array>
   ```

The Simulator shares your Mac's network, so `localhost` reaches your machine.

> Never ship `http` in a release build. Use a separate plist per build
> configuration (for example a Debug-only `SEASecurityConfig.plist` and
> `Info.plist`) so the release app stays `https`-only.

## Logout

Clear SEA's web data (cookies, SSO session) when the user logs out:

```swift
SEASession.purgeWebData {
    // done
}
```

Also end the session on your identity provider (RP-initiated logout) from
your backend.

## Telemetry

Implement `SEATelemetrySink` to receive lifecycle events such as
`AUTH_PAGE_LOADED`, `AUTH_NAV_BLOCKED` and `AUTH_COMPLETED`. Events never
contain credentials, codes or full URLs.

```swift
final class Telemetry: SEATelemetrySink {
    func record(_ event: SEAEvent) { print(event) }
}

let sink = Telemetry()              // keep a strong reference
SEASession.telemetrySink = sink
```

## Errors

| `SEAError` | Meaning |
|---|---|
| `.invalidAuthorizeURL(reason:)` | The URL's scheme or port isn't allowed (`https` on the default port by default), isn't on an allowed domain, or is malformed. Nothing was loaded |
| `.network(underlying:)` | No connectivity, DNS or TLS failure |
| `.serverError(statusCode:)` | The login page returned an HTTP 5xx |
| `.timeout` | The session exceeded `timeoutMs` |
| `.webauthnUnavailable` | The system-browser fallback couldn't start (usually a missing `CallbackScheme`) |

## Troubleshooting

- **The login screen closes immediately with `invalidAuthorizeURL`.** Check
  that the authorize URL's host is in `AuthDomains` *and* `WKAppBoundDomains`.
- **The passkey button never appears.** The Associated Domains entitlement or
  the `apple-app-site-association` file is missing or wrong. SEA silently
  falls back to password login.
- **`pod install` can't find `SEACore`.** The `source` line for this
  repository is missing from your `Podfile`.
