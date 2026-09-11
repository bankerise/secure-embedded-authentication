/**
 * Logout + token-exchange for the demo harness. Pure TypeScript port of
 * apps/demo-ios/Sources/Networking/{TokenExchangeClient,LogoutClient}.swift.
 *
 * Two logout paths, matching the two gateway modes (§6.4):
 *
 *  - **Mock** (`keycloakLogout`): the app itself holds an `id_token` (obtained
 *    via `exchangeCodeForTokens`), so it performs RP-initiated logout with a
 *    GET to the end-session endpoint carrying `id_token_hint`. Keycloak
 *    invalidates the SSO session purely from the token — no session cookie
 *    needed — which is why it works even though the Keycloak SSO cookie lives
 *    in the WebView's separate WKWebsiteDataStore, unreachable from RN's fetch.
 *
 *  - **Real** (`gatewayLogout`): the app never holds a token, so it asks the
 *    gateway (`POST /gw/logout`) which returns the Keycloak logout URL already
 *    enriched with `id_token_hint`, to be invoked separately from the app.
 *
 * Cookie-jar note: unlike the native demo (which had to hand-pick URLSession
 * cookie storages), RN's fetch does NOT share cookies with the WebView jar (so
 * `keycloakLogout` is inherently cookieless) but DOES share one jar across all
 * RN fetches (so `gatewayLogout` automatically carries the `SESSION` cookie
 * that gateway.ts's start hops established). Both §6.5 concerns fall out for free.
 */

export type Tokens = Readonly<{
  idToken: string;
  accessToken?: string;
  expiresIn?: number;
}>;

import { keycloakSiblingEndpoint, queryValue } from './keycloakEndpoints';

function formEncode(pairs: ReadonlyArray<readonly [string, string]>): string {
  return pairs
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

/**
 * Mock-gateway-only PKCE authorization-code → token exchange, run straight
 * against Keycloak's token endpoint, ONLY so the demo can obtain an `id_token`
 * for `id_token_hint`. Not how a real integration works — there the exchange
 * is server-side and the app never sees a token (§6.4). `codeVerifier` is the
 * known constant that pairs with the mock authorize URL's `code_challenge`.
 */
export async function exchangeCodeForTokens(
  code: string,
  authorizeUrl: string,
  codeVerifier: string
): Promise<Tokens> {
  const tokenUrl = keycloakSiblingEndpoint(authorizeUrl, 'token');
  const clientId = queryValue(authorizeUrl, 'client_id');
  const redirectUri = queryValue(authorizeUrl, 'redirect_uri');
  if (!tokenUrl || !clientId || !redirectUri) {
    throw new Error('Could not derive the token endpoint from the authorize URL.');
  }

  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
    },
    body: formEncode([
      ['grant_type', 'authorization_code'],
      ['code', code],
      ['client_id', clientId],
      ['redirect_uri', redirectUri],
      ['code_verifier', codeVerifier],
    ]),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Token endpoint returned HTTP ${response.status}: ${text}`);
  }

  let object: Record<string, unknown>;
  try {
    object = JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new Error(`Failed to decode token response: ${text}`);
  }

  const idToken = object.id_token;
  if (typeof idToken !== 'string') {
    throw new Error(
      `Token response had no id_token (keys: ${Object.keys(object).join(', ')}). ` +
        'Ensure the `openid` scope is requested.'
    );
  }
  return {
    idToken,
    accessToken: typeof object.access_token === 'string' ? object.access_token : undefined,
    expiresIn: typeof object.expires_in === 'number' ? object.expires_in : undefined,
  };
}

/**
 * Mock path: cookieless GET to `…/openid-connect/logout?id_token_hint=<idToken>`.
 * Resolves on any <400 (Keycloak renders a logged-out info page); throws on 4xx/5xx.
 */
export async function keycloakLogout(idToken: string, authorizeUrl: string): Promise<void> {
  const logoutBase = keycloakSiblingEndpoint(authorizeUrl, 'logout');
  if (!logoutBase) {
    throw new Error('Could not derive the logout endpoint from the authorize URL.');
  }
  const url = `${logoutBase}?id_token_hint=${encodeURIComponent(idToken)}`;
  const response = await fetch(url, { method: 'GET' });
  if (response.status >= 400) {
    const text = await response.text();
    throw new Error(`Logout endpoint returned HTTP ${response.status}: ${text}`);
  }
}

/**
 * Real path: `POST {baseURL}/gw/logout` (RN's shared cookie jar carries the
 * `SESSION` cookie from the start hops). Returns the Keycloak logout URL the
 * gateway builds (already carrying `id_token_hint`), to be called separately
 * from this app — this method deliberately does NOT call it.
 */
export async function gatewayLogout(gatewayBaseURL: string): Promise<string> {
  const base = gatewayBaseURL.replace(/\/+$/, '');
  const url = `${base}/gw/logout`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { Accept: 'application/json, text/plain, */*' },
  });

  
  
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Logout endpoint returned HTTP ${response.status}: ${text}`);
  }
  const extracted = extractLogoutURL(text);
  console.log('extracted ', extracted);
  if (extracted) return extracted;
  throw new Error(`Gateway /gw/logout response had no logout URL: ${text}`);
}


/**
 * The exact `/gw/logout` JSON shape isn't pinned by the contract, so be
 * permissive: accept a JSON object under any of a few likely keys, else a
 * bare-string body that already looks like a URL.
 */
function extractLogoutURL(rawBody: string): string | null {
  try {
    const object = JSON.parse(rawBody) as Record<string, unknown>;
    if (object && typeof object === 'object') {
      for (const key of ['logoutUrl', 'redirectUrl', 'redirect', 'url']) {
        const value = object[key];
        if (typeof value === 'string' && value.length > 0) return value;
      }
    }
  } catch {
    // not JSON — fall through to the bare-string check
  }
  const trimmed = rawBody.trim();
  if (trimmed.toLowerCase().startsWith('http')) {
    return trimmed.replace(/^"+|"+$/g, '');
  }
  return null;
}


export async function keycloakSessionLogout(urlKeycloak: string) {
  const response = await fetch(urlKeycloak, {
    method: 'GET',
    headers: { Accept: 'application/json, text/plain, */*' },
  });
  console.log('response logout ', response);
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Logout from keycloak ${response.status}: ${text}`);
  }
  
  
  
  // const text = await response.text();
  // if (!response.ok) {
  //   throw new Error(`Logout endpoint returned HTTP ${response.status}: ${text}`);
  // }
  // const extracted = extractLogoutURL(text);
  // console.log('extracted ', extracted);
  // if (extracted) return extracted;
  // throw new Error(`Gateway /gw/logout response had no logout URL: ${text}`);
}