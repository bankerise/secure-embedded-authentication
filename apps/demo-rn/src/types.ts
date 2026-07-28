import type { SEAError } from '@bankerise-platform/sea-react-native';

export type Result =
  | { kind: 'idle' }
  | { kind: 'captured'; params: Readonly<Record<string, string>>; at: number }
  | { kind: 'cancelled'; at: number }
  | { kind: 'error'; error: SEAError; at: number };

/** Mirrors SEAError.demoDescription (apps/demo-ios/Sources/Models/SessionResultStore.swift). */
export function describeError(error: SEAError): string {
  return error.message ? `${error.code} (${error.message})` : error.code;
}

export function formatTime(at: number): string {
  return new Date(at).toLocaleTimeString();
}
