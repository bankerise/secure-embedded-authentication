# @bankerise/sea-react-native

[![npm](https://img.shields.io/npm/v/%40bankerise%2Fsea-react-native)](https://www.npmjs.com/package/@bankerise/sea-react-native)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/bankerise/secure-embedded-authentication/blob/develop/LICENSE)

A native-feeling, secure login screen for React Native apps that use Keycloak
or any OAuth 2.0 / OpenID Connect provider. It shows your identity provider's
login page **inside your app**, in a locked-down WebView, instead of sending
users out to a browser.

- 🔒 Only your identity provider's domains can load
- 🎯 The OAuth callback is captured in-process and handed to your code
- 🔑 Passkeys supported, with automatic system-browser fallback
- 🎨 Sheet or fullscreen, with your colors and title
- 📱 iOS and Android, built on the native [SEA SDKs](https://github.com/bankerise/secure-embedded-authentication)

This package is a thin wrapper: all the security logic lives in the native
SDKs. [How it works →](https://github.com/bankerise/secure-embedded-authentication/blob/develop/docs/how-it-works.md)

## Requirements

- React Native **0.86+** with the **New Architecture** enabled (Fabric only)
- iOS 15.0+
- Android minSdk 24+, compileSdk 35+

## Installation

```sh
npm install @bankerise/sea-react-native
# or
yarn add @bankerise/sea-react-native
```

### iOS setup

**1. Add the SEA spec source** to `ios/Podfile`, above your target:

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/bankerise/secure-embedded-authentication.git'
```

Then run `cd ios && pod install`.

**2. Add `SEASecurityConfig.plist`** to your app target (Copy Bundle
Resources):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CallbackScheme</key>
    <string>myapp</string>
    <key>AuthDomains</key>
    <array>
        <string>auth.example.com</string>
    </array>
</dict>
</plist>
```

**3. Update `Info.plist`**: list the auth domains as App-Bound Domains and
register the callback scheme:

```xml
<key>WKAppBoundDomains</key>
<array>
    <string>auth.example.com</string>
</array>
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

For passkeys, also add the Associated Domains entitlement
`webcredentials:auth.example.com`.

### Android setup

The native SDK comes from Maven Central, so no Gradle changes are needed.
Create `android/app/src/main/assets/bankerise-sea.properties`:

```properties
callbackScheme=myapp
authDomains=auth.example.com
```

For passkeys, publish a
[Digital Asset Links](https://developer.android.com/identity/sign-in/credential-manager#add-support-dal)
file on your identity provider's domain.

> **Fails closed:** if the config file is missing or incomplete, every
> navigation is blocked and no login can complete. Check this first if the
> login screen closes immediately.

### Local development over `http`

The login page must be `https` by default. To test against a local identity
provider without TLS, allow `http` in debug builds only. On iOS, add
`AllowedSchemes` (and `AllowedPorts` for a non-standard port) to
`SEASecurityConfig.plist` plus an App Transport Security exception; on
Android, add `allowedSchemes=https,http` (and `allowedPorts`) to a
debug-only `bankerise-sea.properties` plus a cleartext network security
config. See the [iOS](https://github.com/bankerise/secure-embedded-authentication/blob/develop/docs/ios.md#local-development-over-http)
and [Android](https://github.com/bankerise/secure-embedded-authentication/blob/develop/docs/android.md#local-development-over-http)
guides.

## Usage

Get an authorize URL from your backend, then mount the component. Unmounting
it closes the login screen, so render it conditionally:

```tsx
import * as React from 'react';
import { SecureAuthenticationView } from '@bankerise/sea-react-native';

function Login({ authorizeUrl }: { authorizeUrl: string }) {
  const [open, setOpen] = React.useState(true);
  if (!open) return null;

  return (
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
      onCaptured={(params) => {
        setOpen(false);
        // Send params.code and params.state to your backend.
      }}
      onCancelled={() => setOpen(false)}
      onError={(error) => {
        setOpen(false);
        console.warn(error.code, error.message);
      }}
    />
  );
}
```

Exactly one of `onCaptured`, `onCancelled` or `onError` fires, once. SEA
never exchanges the code for tokens. That's your backend's job.

### Logout

```tsx
import { purgeWebData } from '@bankerise/sea-react-native';

await purgeWebData(); // clears SEA's cookies and SSO session
```

### Telemetry

```tsx
import { subscribeToTelemetry } from '@bankerise/sea-react-native';

React.useEffect(
  () => subscribeToTelemetry((event) => console.log(event.name, event.properties)),
  []
);
```

## API

### `<SecureAuthenticationView>` props

| Prop | Type | Default | Description |
|---|---|---|---|
| `authorizeUrl` | `string` | required | The authorize URL from your backend. Must be on an allowed domain |
| `presentation` | `'sheet' \| 'fullscreen'` | `'sheet'` | How the login screen is shown |
| `authMode` | `'embedded' \| 'nativeBrowser'` | `'embedded'` | `nativeBrowser` always uses the system browser instead of the WebView |
| `appearance` | `SEAAppearance` | — | Colors and title (see below) |
| `onCaptured` | `(params: Record<string, string>) => void` | — | Login finished. Raw callback parameters (`code`, `state`, …) |
| `onCancelled` | `() => void` | — | The user closed the login screen |
| `onError` | `(error: SEAError) => void` | — | Something went wrong (see error codes) |

### `SEAAppearance`

| Key | Type | Description |
|---|---|---|
| `title` | `string` | Header title. Omit to show the page's own title |
| `headerBackground` | color | Header background |
| `headerText` | color | Header text |
| `accent` | color | Spinner and button tint |
| `closeIconTint` | color | Close button tint |
| `cornerRadius` | `number` | Sheet corner radius (pt on iOS, dp on Android) |

Appearance is read when the screen opens. Changing it while the screen is
open has no effect.

### Error codes

| `error.code` | Meaning |
|---|---|
| `invalid_authorize_url` | The URL's scheme or port isn't allowed (`https` by default) or it isn't on an allowed domain. Nothing was loaded |
| `network` | No connectivity, DNS or TLS failure |
| `server_error` | The login page returned an HTTP 5xx |
| `timeout` | No result within 120 seconds |
| `webauthn_unavailable` | The system-browser fallback couldn't start |

### Other exports

| Export | Description |
|---|---|
| `purgeWebData(): Promise<void>` | Clears SEA's web data. Call it on logout |
| `subscribeToTelemetry(listener): () => void` | Receives SEA lifecycle events. Returns an unsubscribe function |

## Troubleshooting

- **The login screen closes right away with `invalid_authorize_url`.** The
  URL's host isn't in your config file's auth domains (and, on iOS,
  `WKAppBoundDomains`).
- **`pod install` can't find `SEACore`.** The `source` line for the SEA repo
  is missing from your Podfile.
- **"native module is unavailable" warning.** Rebuild the native app after
  installing or updating the package. A JS reload isn't enough.
- **Android `nativeBrowser` mode never returns to the app.** On Android this
  mode currently uses the fixed redirect URI `sea-default-callback://callback`.
  Register it on your OAuth client.

## License

MIT
