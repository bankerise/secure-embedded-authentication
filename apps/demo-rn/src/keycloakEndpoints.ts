/**
 * URL helpers mirroring apps/demo-ios/Sources/Networking/KeycloakEndpoints.swift.
 *
 * Deliberately string-based (no `URL`/`URLSearchParams`): React Native's URL
 * polyfill is incomplete and its `searchParams` has historically been unreliable,
 * so we parse by hand to stay portable across RN versions.
 */

/**
 * Given a Keycloak authorize URL whose path ends in `/auth`, derive the sibling
 * endpoint of the same OIDC realm (e.g. `token`, `logout`) by swapping the last
 * path segment. Query and fragment are dropped. Returns null if the path does
 * not end in `/auth` (i.e. it isn't the authorize endpoint we expect).
 */
export function keycloakSiblingEndpoint(
  authorizeUrl: string,
  name: string
): string | null {
  const path = authorizeUrl.split('#')[0].split('?')[0];
  if (!path.endsWith('/auth')) return null;
  return path.slice(0, -'/auth'.length) + '/' + name;
}

/** First value of query parameter `name` in `rawUrl`, URL-decoded, or null. */
export function queryValue(rawUrl: string, name: string): string | null {
  const query = rawUrl.split('#')[0].split('?')[1];
  if (!query) return null;
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    const key = eq >= 0 ? pair.slice(0, eq) : pair;
    if (safeDecode(key) === name) {
      return safeDecode(eq >= 0 ? pair.slice(eq + 1) : '');
    }
  }
  return null;
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, '%20'));
  } catch {
    return value;
  }
}
