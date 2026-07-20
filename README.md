# Bankerise SEA — Secure Embedded Authentication

Native authentication using hardened embedded WebViews (the Binance / Revolut
pattern), against a bank-owned Keycloak, orchestrated by the Bankerise API
Gateway as confidential OAuth2 client (BFF).

## Specifications

[bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md) — v1.2, normative.

The iOS API contract derived from it:
[docs/api-contract-ios-v1.md](docs/api-contract-ios-v1.md).

## Layout

```
packages/sea-core-ios/     Swift package — the audited security core
apps/demo-ios/             Native device-lab harness (§23.3)
infra/                     Keycloak dev stack + realm export
docs/                      Spec + API contract
```

`sea-core-android` and `sea-react-native` are not started yet — the build is
core-first and iOS-first per §4.8.

## Current status — Phase 1, iOS

Implemented:

- §6.2 authorize-URL integrity validation
- §6.3 in-process callback capture (+ POST-redirect backstop)
- §7.3 deny-by-default navigation policy
- §8.2 hardened `WKWebView` configuration
- §17.1 iOS screen-security posture
- §18.1 sheet presentation, native header, native failure states
- §20.1 telemetry event emission with §20.2 redaction

**Not implemented, deliberately.** These are declared seams, not stubs — nothing
silently succeeds in their place:

| Area | Spec | Status |
|---|---|---|
| Passkeys / WebAuthn | §10 | Out of scope this phase, by decision |
| App Attest | §16 | Phase 2 |
| TLS pinning | §15 | Phase 2 — system chain validation is enforced meanwhile |
| JS bridge | §14 | Not needed; default is no bridge |
| Broker `EXTERNAL_TAB` | §12.4 | Phase 2 |
| Kill-switch fallback | §21 | Phase 2 |
| Android core, RN bridge | §4.2 | Not started |

Because attestation (§16) is the load-bearing compensating control for the §3
RFC-8252 deviation, **this phase is not a security-reviewable configuration.**
It is a functional harness for the §6 handoff perimeter.

## Getting started

```bash
# 1. Keycloak
docker compose -f infra/docker-compose.yml up -d

# 2. Core tests
cd packages/sea-core-ios
xcodebuild test -scheme SEACore -destination 'platform=iOS Simulator,name=iPhone 17'

# 3. Demo app
cd apps/demo-ios
xcodegen generate
open SEADemo.xcodeproj
```

See each directory's README for detail.

## Prerequisites

Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), Docker.
