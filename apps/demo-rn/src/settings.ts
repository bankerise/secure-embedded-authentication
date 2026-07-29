import { ALLOWED_DOMAINS, MOCK_AUTHORIZE_URL } from './mockGateway';
import { getSEAConfigDefaults } from './seaConfigDefaults';

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
  appVersionKey: string;
  callbackScheme: string;
  allowedDomains: string;
  allowedPorts: string;
  maxUrlLengthBytes: number;
  presentation: 'sheet' | 'fullscreen';
  // Runner selection (spec §10.4). 'embedded' (default) is the normal SEA
  // path; 'nativeBrowser' hands the whole login attempt to
  // ASWebAuthenticationSession up front instead.
  authMode: 'embedded' | 'nativeBrowser';
  timeoutMs: number;
  useMockGateway: boolean;
  mockRedirectURL: string;
}>;

function buildDefaults(): Settings {
  try {
    const native = getSEAConfigDefaults();
    return {
      gatewayBaseURL: 'https://showcase-client-gw.demo.proxym-it.net',
      appVersionKey: '4ZvAEYVC2Xk3',
      callbackScheme: native.callbackScheme,
      allowedDomains: native.authDomains,
      allowedPorts: native.allowedPorts,
      maxUrlLengthBytes: native.maxUrlLengthBytes,
      presentation: 'sheet',
      timeoutMs: 120_000,
      useMockGateway: true,
      mockRedirectURL: MOCK_AUTHORIZE_URL,
    };
  } catch {
    // NativeModule unavailable (iOS / test) — use hardcoded fallbacks.
    return {
      gatewayBaseURL: 'http://localhost:8080',
      appVersionKey: '4ZvAEYVC2Xk3',
      callbackScheme: 'bankerise-auth',
      allowedDomains: ALLOWED_DOMAINS.join(','),
      allowedPorts: '-1,443',
      maxUrlLengthBytes: 2048,
      presentation: 'sheet',
      authMode: 'embedded',timeoutMs: 120_000,
      useMockGateway: true,
      mockRedirectURL: MOCK_AUTHORIZE_URL,
    };
  }
}

export const DEFAULT_SETTINGS: Settings = buildDefaults();
console.log('DEFAULT_SETTINGS ', DEFAULT_SETTINGS);

/** Comma list -> trimmed, non-empty array, in the shape SEAConfig expects. */
export function allowedDomainsArray(settings: Settings): string[] {
  return settings.allowedDomains
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}
