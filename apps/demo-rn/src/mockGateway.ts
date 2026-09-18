/**
 * Zero-network stand-in for a real Bankerise API Gateway `/authorization/start`
 * call — mirrors apps/demo-ios/Sources/Networking/MockGateway.swift exactly,
 * so this app exercises the same already-running local infra/ Keycloak
 * (realm `bankerise-mobile`, client `sea-dev-public`) with no new backend.
 *
 * This does NOT bypass sea-react-native/SEACore's own validation (spec
 * §6.2) — the URL still has to be https and host-allowlisted, or the core
 * rejects it via `onError({code: 'invalid_authorize_url'})` exactly as it
 * would for a real gateway response.
 */
export const MOCK_AUTHORIZE_URL =
  'https://auth.bank.local/realms/bankerise-mobile/protocol/openid-connect/auth' +
  '?client_id=sea-dev-public&redirect_uri=bkrmob%3A%2F%2Fcallback' +
  '&response_type=code&scope=openid&state=devstate123' +
  '&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM' +
  '&code_challenge_method=S256';

/**
 * PKCE `code_verifier` that pairs with MOCK_AUTHORIZE_URL's `code_challenge`
 * (`E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`, S256) — the RFC 7636 worked
 * example. Mirrors apps/demo-ios/Sources/Models/AppSettings.swift's
 * `mockCodeVerifier`. Used only by the mock-path token exchange so Logout has
 * an `id_token_hint`; never a real secret.
 */
export const MOCK_CODE_VERIFIER = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

export async function startAuthorization(
  redirectUrl: string = MOCK_AUTHORIZE_URL
): Promise<{ authorizeUrl: string; authMode: string; provider: string }> {
  // Small artificial delay so a loading state is actually visible, same as
  // the native mock.
  await new Promise<void>((resolve) => setTimeout(resolve, 250));
  return { authorizeUrl: redirectUrl, authMode: 'EMBEDDED', provider: 'mock' };
}
