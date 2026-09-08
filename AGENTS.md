# AGENTS.md

## Repository overview

Bankerise SEA (Secure Embedded Authentication) — hardened embedded WebView auth
for iOS using Keycloak, with a React Native Fabric bridge. Spec-driven; the
normative spec is `bankerise_sea_specs-v1.0.md` and the iOS API contract is
`docs/api-contract-ios-v1.md`.

## Structure

```
packages/sea-core-ios/       Swift package — the audited security core
packages/sea-react-native/   Fabric bridge wrapping sea-core-ios
packages/sea-core-android/   Android core library, distributed via JitPack
apps/demo-ios/               Native device-lab harness (XcodeGen)
apps/demo-rn/                RN bridge validation harness
infra/                       Keycloak dev stack + realm provisioning
themes/                      Keycloak login themes (mounted into Docker)
Specs/                       Per-package spec snapshots
```

## Commands

### Core tests (Swift)

```bash
cd packages/sea-core-ios
xcodebuild test -scheme SEACore -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Demo app — native (XcodeGen)

```bash
cd apps/demo-ios
xcodegen generate
open SEADemo.xcodeproj
```

`SEADemo.xcodeproj` is generated, never committed. Re-run `xcodegen generate`
whenever `project.yml` or `Sources/` layout changes.

### Demo app — React Native bridge

From repo root:

```bash
nvm use && yarn install                      # Node >=22.13, Yarn classic
cd apps/demo-rn/ios && pod install && cd ..  # ~3 min first run
yarn ios
```

Metro resolves `sea-react-native` to its TS source directly via
`sea-react-native-source` export condition — no `bob build` step needed in dev.

### Keycloak dev stack

```bash
cd infra
brew install mkcert jq          # one-time
./gen-certs.sh
docker compose up -d
./provision-realm.sh            # idempotent; creates realm, clients, demo user
```

**Manual step required**: `echo '127.0.0.1 auth.bank.local' | sudo tee -a /etc/hosts`
The passkey RP ID and iOS Associated Domain are both fixed to `auth.bank.local`.

### React Native bridge package scripts

```bash
cd packages/sea-react-native
yarn typecheck       # tsc (no emit, strict mode)
yarn lint            # eslint + prettier
yarn test            # jest
yarn prepare         # bob build (for publish only)
```

### Demo RN scripts

```bash
cd apps/demo-rn
yarn lint
yarn test
```

## Key conventions

- **Spec references are everywhere.** Files cite spec sections (§6.2, §7.3,
  §10, etc.) by number. When modifying code, check the corresponding spec
  section — the spec is the source of truth, not the code.
- **No debug TLS bypass.** The authorize-URL validator requires `https` with
  no exception for debug builds (§8.2). Local dev uses nginx + mkcert TLS
  termination, not a weakened validator. Never add an `http` bypass.
- **XcodeGen, not committed Xcode projects.** `apps/demo-ios/SEADemo.xcodeproj`
  is gitignored. The source of truth is `apps/demo-ios/project.yml`.
- **SEACore is consumed two ways.** SwiftPM (by `demo-ios`, path:
  `../../packages/sea-core-ios`) and CocoaPods (by `demo-rn` via local `:path`
  in `Podfile`). The podspec is a thin wrapper — same `Sources/SEACore` code.
- **The `#if SWIFT_PACKAGE` seam in `SEAStrings.swift`** handles the
  `Bundle.module` difference between SwiftPM and CocoaPods.
- **React Native bridge purity rule (§7.4).** All bridge logic lives in
  `packages/sea-react-native/ios/SEABridgePresenter.swift`. The generated
  Fabric view (`SeaReactNativeView.mm`) only marshals props/events.
- **CocoaPods `:path` for local dev.** `sea-core-ios` is consumed by `demo-rn`
  via a local CocoaPods path reference, not a published pod. This is
  intentional per §4.5.
- **Keycloak auth flow nesting.** The `browser-passkey` flow MUST nest the
  passkey/password ALTERNATIVE siblings under their own REQUIRED subflow.
  Mixing REQUIRED and ALTERNATIVE at the same level causes Keycloak 26.6 to
  throw `AuthenticationFlowException` (HTTP 400). See `infra/README.md` for
  the full explanation.
- **Theme import-map.** `themes/bankerise-mobile/login/template.ftl` MUST emit
  the `rfc4648` import map for WebAuthn modules. Without it, passkey
  registration/authentication silently fails inside WKWebView.
- **Both demo apps must be listed in AASA.** `infra/nginx/apple-app-site-association`
  must include both `TEAMID.com.bankerise.sea.demo` and
  `TEAMID.com.bankerise.sea.demorn`. Replace `TEAMID` with your actual Apple
  Team ID. Missing entries cause WebAuthn to silently skip Associated Domain
  binding.
- **Yarn classic (v1) workspaces.** Root `package.json` defines workspaces for
  `packages/sea-react-native` and `apps/demo-rn`. Do not upgrade to Yarn
  berry without testing the full RN toolchain.
- **`sea-react-native` publishes to a private Nexus npm registry.** The
  `publishConfig` in `packages/sea-react-native/package.json` points at
  `repos.proxym-group.net`. Do not `npm publish` from a local machine
  without the proper auth token setup.

## Testing

- Core Swift tests: `xcodebuild test` (see above). Test fixtures are in
  `packages/sea-core-ios/Tests/SEACoreTests/Fixtures/`.
- React Native bridge tests: `cd packages/sea-react-native && yarn test`
- Demo RN tests: `cd apps/demo-rn && yarn test`
- UI tests exist in `apps/demo-ios/UITests/` — end-to-end device-lab smoke
  tests (§23.3). Run via Xcode scheme (they're wired into the `SEADemo`
  scheme's test targets).
- Validate passkey ceremony in a desktop browser **before** touching the
  Simulator (Chrome DevTools → WebAuthn → virtual authenticator). See
  `infra/README.md` for the procedure.

## Gotchas

- `apps/demo-ios/Sources/Info.plist` has a DEV-ONLY ATS exception for
  `localhost`. This must never ship — delete the `NSAppTransportSecurity`
  block before any non-dev build.
- `docker compose ps` may show `sea-keycloak-tls` as `unhealthy` even when
  everything works (IPv6 resolver artifact inside the container). Safe to
  ignore; host-side `curl`/WKWebView are unaffected.
- After regenerating TLS certs (`./gen-certs.sh`), re-run
  `./trust-ca-simulator.sh` — the simulator keychain won't trust the new cert
  until you do.
- The `TEAMID` placeholder in AASA is a known setup step — replace it with
  your real Apple Team ID before testing passkeys on a device or simulator.
- `apps/demo-rn` settings are in-memory only (no persistence across launches),
  unlike `apps/demo-ios` which uses `UserDefaults`.
