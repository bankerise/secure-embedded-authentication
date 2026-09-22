# SEA — Secure Embedded Authentication

[![CI](https://github.com/bankerise/secure-embedded-authentication/actions/workflows/ci.yml/badge.svg)](https://github.com/bankerise/secure-embedded-authentication/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/%40bankerise%2Fsea-react-native?label=npm)](https://www.npmjs.com/package/@bankerise/sea-react-native)
[![Maven Central](https://img.shields.io/maven-central/v/com.bankerise/sea-core-android?label=maven%20central)](https://central.sonatype.com/artifact/com.bankerise/sea-core-android)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A native-feeling login screen for mobile apps that authenticate with Keycloak
or any OAuth 2.0 / OpenID Connect provider — without sending users out to a
browser.**

The usual way to log in on mobile is to open the provider's page in the system
browser (`ASWebAuthenticationSession` on iOS, Custom Tabs on Android). It's
secure, but users see an address bar, browser chrome and a jarring jump out of
your app — right on your front door.

SEA shows the same login page **inside your app**, in a locked-down WebView
that keeps the safety properties of the browser approach:

- 🔒 **Only your identity provider can load** — every navigation is checked
  against an allowlist you control; everything else is blocked.
- 🎯 **The OAuth callback never leaves the app** — the authorization `code` is
  captured in-process and handed straight to your code.
- 🔑 **Passkeys work** — WebAuthn runs inside the embedded view, with an
  automatic fallback to the system browser on devices that can't.
- 🙈 **Screen-capture aware** — screenshots and recordings of the login screen
  are detected and mitigated.
- 🎨 **Looks like your app** — sheet or fullscreen presentation, your colors,
  your title.
- 📱 **iOS, Android and React Native** — native SDKs plus a thin React Native
  wrapper.

SEA's job ends once it hands you the callback parameters (`code`, `state`, …).
Exchanging the code for tokens and managing the session stays with your
backend, exactly as in a standard OAuth flow.

## Packages

| Platform | Package | Install |
|---|---|---|
| iOS | `SEACore` | CocoaPods — [iOS guide](docs/ios.md) |
| Android | `com.bankerise:sea-core-android` | Maven Central — [Android guide](docs/android.md) |
| React Native | `@bankerise/sea-react-native` | npm — [React Native guide](packages/sea-react-native/README.md) |

## Quick look

**React Native**

```tsx
import { SecureAuthenticationView } from '@bankerise/sea-react-native';

<SecureAuthenticationView
  authorizeUrl={authorizeUrl}              // from your backend
  presentation="sheet"
  appearance={{ title: 'Sign in', accent: '#3D8BFF' }}
  onCaptured={(params) => exchangeCode(params.code, params.state)}
  onCancelled={() => {}}
  onError={(error) => console.warn(error.code)}
/>
```

**iOS**

```swift
import SEACore

SEASession.start(
    config: SEAConfig(authorizeURL: authorizeURL),
    from: viewController,
    callbacks: .init(
        onCaptured: { params in exchangeCode(params.code, params.state) },
        onCancelled: { },
        onError: { error in print(error) }
    )
)
```

**Android**

```kotlin
import com.bankerise.sea.core.*

SEASession.start(
    activity = this,
    config = SEAConfig(
        authorizeUrl = Uri.parse(authorizeUrl),
        callbackScheme = "myapp",
        allowedDomains = listOf("auth.example.com"),
    ),
    callbacks = SEASession.Callbacks(
        onCaptured = { params -> exchangeCode(params.code, params.state) },
        onCancelled = { },
        onError = { error -> Log.w("SEA", error.toString()) },
    ),
)
```

Each platform also needs a small security config (your callback scheme and
allowed domains) — see the guides.

## Requirements

| | Minimum |
|---|---|
| iOS | 15.0, Swift 5.9 |
| Android | API 24 (Android 7.0), Kotlin, JDK 17 |
| React Native | 0.86 with the New Architecture (Fabric) enabled |
| Identity provider | Any OAuth 2.0 / OIDC provider; tested with Keycloak 26 |

## Documentation

- [How it works](docs/how-it-works.md) — the login flow and the security model, in plain terms
- Guides: [iOS](docs/ios.md) · [Android](docs/android.md) · [React Native](packages/sea-react-native/README.md)
- [Running the demo apps](docs/demo-apps.md) — try SEA against a local Keycloak in a few minutes
- [Design documents](docs/design/) — full specification, threat model and API contracts

## Repository layout

```
packages/
  sea-core-ios/        iOS SDK (Swift)
  sea-core-android/    Android SDK (Kotlin)
  sea-react-native/    React Native wrapper (Fabric)
apps/
  demo-ios/            Native iOS demo app
  demo-android/        Native Android demo app
  demo-rn/             React Native demo app
infra/                 Local Keycloak stack for development
themes/                Mobile-optimized Keycloak login theme
docs/                  Guides and design documents
```

## Contributing

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) to get set
up, and please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

Found a security issue? Please **don't** open a public issue — see
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Bankerise
