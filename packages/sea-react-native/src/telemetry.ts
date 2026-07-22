import { NativeEventEmitter, NativeModules } from 'react-native';

// SEAEvent (spec §20.1) — crosses the bridge unchanged, same "mechanical
// marshalling" rule as SEAError/SEACallbackParams (§7.4).
export type SEATelemetryEvent = Readonly<{
  name: string;
  properties: Readonly<Record<string, string>>;
  timestampMs: number;
}>;

const { SeaTelemetryEmitter } = NativeModules;

/**
 * Subscribes to every SEAEvent SEACore emits (spec §20) for as long as at
 * least one subscriber is active. Returns an unsubscribe function.
 */
export function subscribeToTelemetry(
  listener: (event: SEATelemetryEvent) => void
): () => void {
  const emitter = new NativeEventEmitter(SeaTelemetryEmitter);
  const subscription = emitter.addListener('SeaTelemetryEvent', (event: Object) =>
    listener(event as SEATelemetryEvent)
  );
  return () => subscription.remove();
}

/** Copies text to the system clipboard (demo-harness convenience only). */
export function copyToClipboard(text: string): void {
  SeaTelemetryEmitter.copyToClipboard(text);
}

/** Spec §11.3 step 2 — purges the shared WKWebsiteDataStore. */
export function purgeWebData(): Promise<void> {
  return SeaTelemetryEmitter.purgeWebData();
}
