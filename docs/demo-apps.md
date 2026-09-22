# Running the demo apps

Three demo apps let you try SEA end to end against a local Keycloak. Each
has a mock-gateway mode, so no backend is needed.

| App | What it's for |
|---|---|
| `apps/demo-ios` | Native iOS (SwiftUI) |
| `apps/demo-android` | Native Android (Jetpack Compose) |
| `apps/demo-rn` | React Native, using `@bankerise/sea-react-native` from source |

## 1. Start Keycloak

The local stack runs Keycloak behind an nginx TLS proxy on
`https://auth.bank.local`, so the demos use the same `https`-only defaults as
production. (SEA can be configured for plain `http` in development, see the
[iOS](ios.md#local-development-over-http) and
[Android](android.md#local-development-over-http) guides.)

```bash
brew install mkcert jq
cd infra
./gen-certs.sh                 # local TLS certificate
docker compose up -d
./provision-realm.sh           # realm, clients, demo user, passkeys
```

Add the hostname once (needs sudo):

```bash
echo '127.0.0.1 auth.bank.local' | sudo tee -a /etc/hosts
```

For the iOS Simulator, trust the local certificate:

```bash
./trust-ca-simulator.sh
```

Log in with **`demo` / `demo123`**. The admin console is at
https://auth.bank.local/admin (`admin` / `admin`).

> Everything in `infra/` is for local development only. It's not a production
> setup.

## 2. Run a demo

**iOS** (Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
cd apps/demo-ios
xcodegen generate
open SEADemo.xcodeproj
```

**Android** (Android Studio): open `apps/demo-android` and run the `app`
configuration. Emulators don't read your Mac's `/etc/hosts`, so use the
app's Config screen to point it at a Keycloak host the emulator can reach.

**React Native** (Node 22.13+, Yarn 1):

```bash
nvm use && yarn install        # from the repo root
cd apps/demo-rn/ios && pod install && cd ..
yarn ios                       # or: yarn android
```

## What to try

- **Config**: switch between sheet and fullscreen, change colors, or force
  `nativeBrowser` mode.
- **Start login**: sign in with a password, or enroll and use a passkey.
- **Result**: the captured callback parameters.
- **Telemetry**: live SEA events as you interact.
- **Fuzz** (iOS): runs hostile URLs through the validator to show they're
  blocked.

## More detail

[infra/README.md](../infra/README.md) covers passkey setup, Apple App Site
Association, the Keycloak auth flow, and troubleshooting.
