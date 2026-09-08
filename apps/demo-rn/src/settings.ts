import { MOCK_AUTHORIZE_URL } from './mockGateway';

/**
 * Tester-facing configuration for the demo harness (mirrors
 * apps/demo-ios/Sources/Models/AppSettings.swift). This is harness state
 * only — it has no bearing on SEACore's own security posture.
 *
 * Simplification vs. the iOS demo: kept in memory (React state) rather than
 * persisted across launches — no UserDefaults-equivalent dependency in this
 * bridge-validation harness.
 *
 * Security knobs (callback scheme, allowed domains, allowed ports, max URL
 * length, timeout) are deliberately NOT here: they are enforced by the
 * native platform config — `bankerise-sea.properties` on Android and
 * `SEASecurityConfig.plist` on iOS — and are no longer props on
 * `SecureAuthenticationView`.
 */
export type Settings = Readonly<{
  gatewayBaseURL: string;
  appVersionKey: string;
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
    presentation: 'sheet',
    authMode: 'embedded',
    timeoutMs: 120_000,
    useMockGateway: true,
    mockRedirectURL: MOCK_AUTHORIZE_URL,
  };
}

export const DEFAULT_SETTINGS: Settings = buildDefaults();
