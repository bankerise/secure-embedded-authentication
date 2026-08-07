# sea-react-native

Thin Fabric bridge wrapping `sea-core-ios` (spec §7). No authentication,
navigation, storage, crypto, or networking logic of its own — see
`ios/SEABridgePresenter.swift` for the entire bridge-side logic (marshals
primitive props into a `SEAConfig`, calls `SEASession.start`) and
`ios/SeaReactNativeView.mm` for the generated Fabric glue.

Consumed in this monorepo via Yarn workspaces by `apps/demo-rn` — see
[infra/README.md](../../infra/README.md#sea-react-native-bridge--appsdemo-rn-spec-42-44-7)
for the dev-mode setup (this package is not published to npm; `sea-core-ios`
is consumed via CocoaPods local `:path`, spec §4.5).

## Usage

```tsx
import { SecureAuthenticationView } from 'sea-react-native';

<SecureAuthenticationView
  authorizeUrl={authorizeUrl}
  presentation="sheet"
  onCaptured={(params) => {/* raw callback query params */}}
  onCancelled={() => {}}
  onError={(error) => {/* {code, message?} — SEAError taxonomy, spec §7.2 */}}
/>
```

Only per-session/UI values are props. The security knobs (allowed domains,
callback scheme, allowed ports, max URL length, timeout) are **not** exposed
on the bridge — they are owned by the native platform config: the host app's
`SEASecurityConfig.plist` on iOS (read by `SEAEnvironment`) and its
`bankerise-sea.properties` on Android (read by `SEAPropertiesLoader`).

## Telemetry, purge, clipboard (debug-harness API)

Separate from the Fabric view: a small `SeaTelemetryEmitter` native module
(`ios/SeaTelemetryEmitter.swift`) registers itself as `SEASession.telemetrySink`
while at least one JS listener is subscribed, so a host app can observe every
§20 `SEAEvent` SEACore emits.

```ts
import { subscribeToTelemetry, purgeWebData, copyToClipboard } from 'sea-react-native';

const unsubscribe = subscribeToTelemetry((event) => {
  console.log(event.name, event.properties, event.timestampMs);
});

await purgeWebData(); // spec §11.3 step 2 — clears the shared WKWebsiteDataStore
```

## License

MIT

---

Scaffolded with [create-react-native-library](https://github.com/callstack/react-native-builder-bob).
