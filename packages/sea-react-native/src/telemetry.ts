import { NativeEventEmitter, NativeModules } from 'react-native';

// SEAEvent (spec §20.1) — crosses the bridge unchanged, same "mechanical
// marshalling" rule as SEAError/SEACallbackParams (§7.4).
export type SEATelemetryEvent = Readonly<{
  name: string;
  properties: Readonly<Record<string, string>>;
  timestampMs: number;
}>;

const { SeaTelemetryEmitter } = NativeModules;

// Guard against the native module being absent from the running binary (e.g.
// the app was launched from a build made before this module was added, so no
// native rebuild has happened yet). Without this, `new NativeEventEmitter(null)`
// throws and red-screens the whole Telemetry tab instead of degrading quietly.
function warnUnavailable(): void {
  console.warn(
    'SeaTelemetryEmitter native module is unavailable — telemetry/purge/clipboard ' +
      'are disabled. Rebuild the app (pod install + native build) to include it.'
  );
}

/**
 * Subscribes to every SEAEvent SEACore emits (spec §20) for as long as at
 * least one subscriber is active. Returns an unsubscribe function. No-ops if
 * the native module is unavailable.
 */
export function subscribeToTelemetry(
  listener: (event: SEATelemetryEvent) => void
): () => void {
  if (SeaTelemetryEmitter == null) {
    warnUnavailable();
    return () => {};
  }
  const emitter = new NativeEventEmitter(SeaTelemetryEmitter);
  const subscription = emitter.addListener('SeaTelemetryEvent', (event: Object) =>
    listener(event as SEATelemetryEvent)
  );
  return () => subscription.remove();
}

/** Copies text to the system clipboard (demo-harness convenience only). */
export function copyToClipboard(text: string): void {
  if (SeaTelemetryEmitter == null) {
    warnUnavailable();
    return;
  }
  SeaTelemetryEmitter.copyToClipboard(text);
}

/** Spec §11.3 step 2 — purges the shared WKWebsiteDataStore. */
export function purgeWebData(): Promise<void> {
  if (SeaTelemetryEmitter == null) {
    warnUnavailable();
    return Promise.resolve();
  }
  return SeaTelemetryEmitter.purgeWebData();
}
