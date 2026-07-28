# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this
project is pre-1.0, so breaking changes may land in any `0.x` release.

## [Unreleased]

- `SEAConfig.authMode` (`.embedded` default | `.nativeBrowser`): lets a caller
  explicitly route the whole login attempt to `ASWebAuthenticationSession`
  instead of the embedded WebView, reusing the §10.4 fallback runner.
  Exposed through to `sea-react-native` as the `authMode` prop on
  `SecureAuthenticationView`, and as a toggle in `demo-rn`'s Config screen.

## sea-core-ios/0.0.1 — 2026-07

- Initial CocoaPods release: embedded WebView auth core, §10.4 WebAuthn
  capability fallback (`ASWebAuthenticationSession`), §11.3 RP-initiated
  logout.

## sea-react-native/0.0.1 — 2026-07

- Initial npm release: Fabric bridge (`SecureAuthenticationView`) wrapping
  `sea-core-ios`, plus the telemetry/purge-web-data module and logout hook.
