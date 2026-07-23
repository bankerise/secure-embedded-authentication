import { ALLOWED_DOMAINS, MOCK_AUTHORIZE_URL } from './mockGateway';

/**
 * Tester-facing configuration for the demo harness (mirrors
 * apps/demo-ios/Sources/Models/AppSettings.swift). This is harness state
 * only — it has no bearing on SEACore's own security posture.
 *
 * Simplification vs. the iOS demo: kept in memory (React state) rather than
 * persisted across launches — no UserDefaults-equivalent dependency in this
 * bridge-validation harness.
 */
export type Settings = Readonly<{
  gatewayBaseURL: string;
  allowedDomains: string;
  presentation: 'sheet' | 'fullscreen';
  timeoutMs: number;
  useMockGateway: boolean;
  mockRedirectURL: string;
}>;

export const DEFAULT_SETTINGS: Settings = {
  // Our own gateway.ts <-> local backend traffic. Not passed to SEACore.
  gatewayBaseURL: 'http://localhost:8080',
  allowedDomains: ALLOWED_DOMAINS.join(','),
  presentation: 'sheet',
  timeoutMs: 120_000,
  useMockGateway: true,
  mockRedirectURL: MOCK_AUTHORIZE_URL,
};

/** Comma list -> trimmed, non-empty array, in the shape SEAConfig expects. */
export function allowedDomainsArray(settings: Settings): string[] {
  return settings.allowedDomains
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}
