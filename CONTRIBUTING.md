# Contributing to SEA

Thanks for helping out! Bug reports, docs fixes and code are all welcome.
Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

> **Security issues:** please don't open a public issue. See
> [SECURITY.md](SECURITY.md).

## Getting set up

| Tool | Version | Needed for |
|---|---|---|
| Xcode + CocoaPods | Xcode 26+ | iOS SDK, iOS and RN demos |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | latest | iOS demo |
| Android Studio + JDK 17 | — | Android SDK and demo |
| Node + Yarn 1 | Node 22.13+ (see `.nvmrc`) | React Native package and demo |
| Docker | — | Local Keycloak |

```bash
git clone https://github.com/bankerise/secure-embedded-authentication.git
cd secure-embedded-authentication
nvm use && yarn install
```

To run everything against a local Keycloak, see
[docs/demo-apps.md](docs/demo-apps.md).

## Running the checks

```bash
# iOS SDK
cd packages/sea-core-ios
xcodebuild test -scheme SEACore -destination 'platform=iOS Simulator,name=iPhone 17'

# Android SDK (the Gradle build lives in the demo app)
cd apps/demo-android
./gradlew :sea-core-android:testReleaseUnitTest

# React Native package
cd packages/sea-react-native
yarn typecheck && yarn lint && yarn test
```

CI runs the same checks on every pull request.

## Ground rules

These keep SEA secure, so reviews enforce them:

- **Security logic lives in the native SDKs only.** `sea-react-native` just
  passes props in and events out. It must not use networking, crypto,
  storage or WebView APIs.
- **The allowlist can only be narrowed.** Domains passed at runtime are
  intersected with the app's bundled config, never added to it.
- **Secure by default.** The SDKs load `https` only unless the host app's
  *bundled* config opts in to `http` (`AllowedSchemes` / `allowedSchemes`)
  for local development. Never add runtime switches, TLS-validation
  exceptions or a hidden "dev mode" to the SDKs. The demo stack in `infra/`
  uses real HTTPS.
- **iOS and Android stay in sync.** A behavior change in one SDK needs the
  matching change in the other, or an issue tracking it.
- **Behavior changes update the spec.** If you change how SEA behaves, update
  [docs/design/specification.md](docs/design/specification.md) in the same
  pull request. Code comments like `§6.2` refer to its sections.

## Pull requests

1. Fork the repo and branch off `develop`.
2. Keep each PR focused on one package or concern.
3. Use [Conventional Commits](https://www.conventionalcommits.org/):
   `fix(sea-core-ios): reject userinfo in authorize URL`.
4. Say how you tested it. For UI or login-flow changes, "it builds" isn't
   enough. Include a simulator or device run.
5. Add a line to [CHANGELOG.md](CHANGELOG.md) under *Unreleased* if users
   will notice the change.

## Releasing (maintainers)

Each package is released independently by pushing a tag. GitHub Actions does
the rest.

| Package | Tag | Published to |
|---|---|---|
| iOS `SEACore` | `sea-core-ios/X.Y.Z` | CocoaPods spec index in this repo (`Specs/`) |
| Android `sea-core-android` | `sea-core-android/X.Y.Z` | Maven Central |
| React Native `@bankerise/sea-react-native` | `sea-react-native/X.Y.Z` | npm |

**Android and React Native.** The version comes from the tag:

```bash
git tag sea-core-android/0.0.2 && git push origin sea-core-android/0.0.2
git tag sea-react-native/0.0.2 && git push origin sea-react-native/0.0.2
```

If a React Native release needs a new Android SDK version, release the
Android SDK first, then bump `seaCoreAndroidVersion` in
`packages/sea-react-native/android/build.gradle.kts`.

**iOS.** Bump `s.version` in `packages/sea-core-ios/SEACore.podspec`,
regenerate the spec index entry and commit it *before* tagging (CI checks
they match):

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
VERSION=0.0.2
mkdir -p Specs/SEACore/$VERSION
pod ipc spec packages/sea-core-ios/SEACore.podspec > Specs/SEACore/$VERSION/SEACore.podspec.json
git add packages/sea-core-ios/SEACore.podspec Specs/SEACore/$VERSION
git commit -m "chore(sea-core-ios): release $VERSION"
git tag sea-core-ios/$VERSION && git push origin develop sea-core-ios/$VERSION
```

**Repository secrets**

| Secret | Used for |
|---|---|
| `SONATYPE_USERNAME` / `SONATYPE_PASSWORD` | Maven Central. A Central Portal *user token*, not your login |
| `GPG_SIGNING_KEY` / `GPG_SIGNING_PASSWORD` | Signing Maven artifacts. ASCII-armored private key and passphrase. The public key must be on `keyserver.ubuntu.com` |

npm needs no secret: `@bankerise/sea-react-native` uses
[trusted publishing](https://docs.npmjs.com/trusted-publishers), linked to
`.github/workflows/sea-react-native.yml`. If you rename that workflow, update
the trusted publisher on npmjs.com too.
