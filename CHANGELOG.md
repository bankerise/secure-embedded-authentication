# Changelog

All notable changes to SEA are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). SEA is pre-1.0, so
any `0.0.x` release may contain breaking changes.

Each package is versioned independently: `SEACore` (iOS),
`sea-core-android` and `@bankerise/sea-react-native`.

## [Unreleased]

## 0.0.1 — first public release

First release of all three packages.

- **iOS (`SEACore`)** and **Android (`sea-core-android`)**: embedded
  WebView login with authorize-URL validation, deny-by-default navigation,
  in-process callback capture, passkeys with automatic system-browser
  fallback, `authMode` to force the system browser, screen-capture
  detection, sheet/fullscreen presentation with custom appearance,
  telemetry events, and `purgeWebData` for logout.
- **Local development:** both SDKs can opt in to plain `http` and
  non-standard ports through their bundled config (`AllowedSchemes` /
  `AllowedPorts` on iOS, `allowedSchemes` / `allowedPorts` on Android).
  Defaults stay `https` on port 443.
- **React Native (`@bankerise/sea-react-native`)**: `SecureAuthenticationView`
  Fabric component wrapping both SDKs, plus `subscribeToTelemetry` and
  `purgeWebData`.
- Distribution: CocoaPods (spec index in this repo), Maven Central and npm.
