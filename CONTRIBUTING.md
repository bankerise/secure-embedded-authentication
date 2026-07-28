# Contributing

Thanks for your interest in Bankerise SEA. This is a monorepo containing an
iOS security core, a React Native bridge, and their test/demo harnesses.

## Layout

```
packages/sea-core-ios/     Swift package — the audited security core
packages/sea-react-native/ Fabric bridge wrapping sea-core-ios (spec §7)
apps/demo-ios/              Native device-lab harness
apps/demo-rn/                Bridge validation harness only
infra/                       Keycloak dev stack + realm export
themes/                      Keycloak theme shipped alongside SEA
docs/                        Spec + API contract
```

See [README.md](README.md) for prerequisites and setup, and
[bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md) for the
normative spec every change here should trace back to.

## Ground rules

- **`sea-react-native` is a pure bridge** (spec §4.2/§7.4): it may not import
  networking, crypto, storage, or WebView APIs. All auth logic lives in
  `sea-core-ios`. A CI lint enforces this — don't try to route around it.
- **Don't widen the allowlist model.** Host-supplied `allowedDomains` are
  *intersected* with the compiled-in list, never used to replace or expand
  it (spec §7.1/§7.3).
- Changes to normative behavior should update
  [bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md) in the same PR,
  not as a follow-up.

## Development setup

```bash
# 1. Keycloak
docker compose -f infra/docker-compose.yml up -d

# 2. Core tests
cd packages/sea-core-ios
xcodebuild test -scheme SEACore -destination 'platform=iOS Simulator,name=iPhone 17'

# 3. RN bridge
nvm use && yarn install
cd apps/demo-rn/ios && pod install && cd ..
yarn ios
```

## Commit messages

`sea-react-native` uses [commitlint](https://commitlint.js.org/) with the
conventional-commits preset (`@commitlint/config-conventional`) to drive its
changelog generation. Use `type(scope): summary` — e.g.
`fix(sea-react-native): forward onError code through the Fabric event`.

## Pull requests

- Keep PRs scoped to one package/concern where possible — this is a monorepo
  spanning Swift, TypeScript, and Keycloak theme code, and mixed-concern PRs
  are hard to review.
- State how you verified the change (simulator run, `xcodebuild test`,
  `yarn typecheck`/`lint`/`test`) — "it builds" isn't a verification step for
  UI or auth-flow changes.
- Security-relevant changes: see [SECURITY.md](SECURITY.md) before opening a
  public PR with exploit details.

## Releases

Both `sea-core-ios` (CocoaPods, via the `Specs/` index committed in this
repo) and `sea-react-native` (npm) are released by pushing a tag shaped
`sea-core-ios/X.Y.Z` or `sea-react-native/X.Y.Z`, which triggers the
matching GitHub Actions workflow in `.github/workflows/`.

For `sea-core-ios`, the `Specs/SEACore/<version>/SEACore.podspec.json`
index entry must be regenerated and committed *before* tagging (the
release-gate workflow fails the tag otherwise):

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # CocoaPods needs a UTF-8 locale
# after bumping s.version in SEACore.podspec:
mkdir -p Specs/SEACore/<version>
pod ipc spec packages/sea-core-ios/SEACore.podspec > Specs/SEACore/<version>/SEACore.podspec.json
git add packages/sea-core-ios/SEACore.podspec Specs/SEACore/<version>
git commit -m "Release sea-core-ios <version>"
git tag "sea-core-ios/<version>"
git push origin develop && git push origin "sea-core-ios/<version>"
```
