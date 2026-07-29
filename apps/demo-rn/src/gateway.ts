import { currentDeviceId } from './deviceIdentity';

/**
 * Result of the §6.1 two-hop start sequence: the final Keycloak authorize
 * URL SEACore will validate and load, plus the mode/provider the gateway
 * reported. Mirrors apps/demo-ios/Sources/Networking/AuthGateway.swift.
 */
export type GatewayStartResult = Readonly<{
  authorizeUrl: string;
  authMode: string; // "EMBEDDED" | "SYSTEM_BROWSER" (absent -> EMBEDDED, §21)
  provider: string;
}>;

export class GatewayError extends Error {}

// Default value — overridable via Settings.appVersionKey in the demo harness.
const DEFAULT_APP_VERSION_KEY = '4ZvAEYVC2Xk3';

type StartResponse = { redirect: string; authMode?: string; provider: string };
type RedirectResponse = { redirectUrl: string; provider: string };

async function getJSON<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  const body = await response.text();
  if (!response.ok) {
    throw new GatewayError(`Gateway returned HTTP ${response.status}: ${body}`);
  }
  try {
    return JSON.parse(body) as T;
  } catch (error) {
    throw new GatewayError(
      `Failed to decode gateway response: ${String(error)}`,
    );
  }
}

export function getCurrentUser() {
  fetch('http://showcase-ebanking-ui.local.proxym-it.tn/secured/users/me', {
    method: 'GET',
    credentials: 'include', // Send browser cookies automatically
    headers: {
      Accept: 'application/json, text/plain, */*',
      'Accept-Language': 'ar',
    },
  })
    .then(async response => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${await response.text()}`);
      }
      return response.json();
    })
    .then(data => console.log('data ', data))
    .catch(err => console.error('Error ', err));
}

/**
 * Real implementation of the §6.1 two-hop gateway start sequence. Mirrors
 * GatewayClient.swift; this app has no cookie-jar concern to manage
 * separately since RN's fetch doesn't share cookies with the WebView's
 * WKWebsiteDataStore in the first place (§6.5 is inherently satisfied).
 */
export async function startAuthorization(
  gatewayBaseURL: string,
  appVersionKey: string = DEFAULT_APP_VERSION_KEY,
): Promise<GatewayStartResult> {
  const base = gatewayBaseURL.replace(/\/+$/, '');

  let start: StartResponse;
  try {
    start = await getJSON<StartResponse>(`${base}/authorization`, {
      method: 'GET',
      headers: {
        Accept: 'application/json, text/plain, */*',
        'Accept-Language': 'en-US',
        'X-App-Version-Key': appVersionKey,
        'X-Device-ID': currentDeviceId(),
      },
    });
  } catch (error) {
    if (error instanceof GatewayError) throw error;
    throw new GatewayError(
      `Invalid gateway base URL or network error: ${String(error)}`,
    );
  }

  const redirectUrl = new URL(start.redirect, `${base}/`).toString();
  console.log('redirectUrl ', redirectUrl);

  const redirect = await getJSON<RedirectResponse>(redirectUrl, {
    method: 'GET',
  });
  console.log('redirect ', redirect);

  return {
    authorizeUrl: redirect.redirectUrl,
    // §21: authMode absent from the real response entirely -> absent means EMBEDDED.
    authMode: start.authMode ?? 'EMBEDDED',
    provider: redirect.provider,
  };
}
