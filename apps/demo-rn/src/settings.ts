import { ALLOWED_DOMAINS, MOCK_AUTHORIZE_URL } from './mockGateway';

/**
 * Tester-facing configuration for the demo harness (mirrors
 * apps/demo-ios/Sources/Models/AppSettings.swift). This is harness state
 * only — it has no bearing on SEACore's own security posture.
 *
 * Simplification vs. the iOS demo: kept in memory (React state) rather than
 * persisted across launches — no UserDefaults-equivalent dependency in this
 * bridge-validation harness.
 *
 * All sensitive values were formerly loaded from a native SEAConfigProvider
 * module that read bankerise-sea.properties. That module was removed in the
 * prop-driven refactor; these defaults mirror the properties file values.
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
  return {
    gatewayBaseURL: 'http://localhost:8080',
    appVersionKey: '4ZvAEYVC2Xk3',
    callbackScheme: 'bkrmob',
    allowedDomains: ALLOWED_DOMAINS.join(','),
    allowedPorts: '-1,443',
    maxUrlLengthBytes: 2048,
    presentation: 'sheet',
    authMode: 'embedded',timeoutMs: 120_000,
    useMockGateway: true,
    mockRedirectURL: MOCK_AUTHORIZE_URL,
  };
}

export const DEFAULT_SETTINGS: Settings = buildDefaults();

/** Comma list -> trimmed, non-empty array, in the shape SEAConfig expects. */
export function allowedDomainsArray(settings: Settings): string[] {
  return settings.allowedDomains
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}
