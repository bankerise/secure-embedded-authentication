import { useCallback, useRef, useState } from 'react';
import { exchangeCodeForTokens, gatewayLogout, keycloakLogout } from './logout';
import { MOCK_CODE_VERIFIER } from './mockGateway';
import type { Settings } from './settings';

/**
 * Session/token store + logout runner for the demo harness, collapsed into one
 * hook. Mirrors apps/demo-ios's SessionTokenStore + LogoutRunner:
 *
 *  - `beginSession` is called when a login is presented (records the authorize
 *    URL — needed to derive Keycloak's logout/token endpoints — and whether
 *    this is the mock path).
 *  - `handleCaptured` runs the mock-only PKCE exchange so Logout has an
 *    id_token_hint. On the real path the app never touches tokens (§6.4).
 *  - `logout` branches on the gateway mode.
 *
 * The live session lives in a ref (not state) so the async `handleCaptured` /
 * `logout` closures always read the latest values without stale-closure bugs;
 * the `@Published`-equivalent strings are React state so the UI re-renders.
 */
type Session = { authorizeUrl: string; wasMock: boolean; idToken: string | null };

export type SessionLogout = {
  tokenStatus: string | null;
  isLoggingOut: boolean;
  logoutMessage: string | null;
  gatewayLogoutURL: string | null;
  beginSession: (authorizeUrl: string, wasMock: boolean) => void;
  handleCaptured: (params: Readonly<Record<string, string>>) => void;
  logout: () => void;
};

export function useSessionLogout(settings: Settings): SessionLogout {
  const sessionRef = useRef<Session | null>(null);
  const [tokenStatus, setTokenStatus] = useState<string | null>(null);
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [logoutMessage, setLogoutMessage] = useState<string | null>(null);
  const [gatewayLogoutURL, setGatewayLogoutURL] = useState<string | null>(null);

  const beginSession = useCallback((authorizeUrl: string, wasMock: boolean) => {
    sessionRef.current = { authorizeUrl, wasMock, idToken: null };
    setTokenStatus(
      wasMock ? 'Awaiting capture…' : 'Real gateway — logout goes through POST /gw/logout.'
    );
    setLogoutMessage(null);
    setGatewayLogoutURL(null);
  }, []);

  // Mock path only: exchange the captured code for tokens so Logout has an
  // id_token_hint. Fire-and-forget — the UI reflects progress via tokenStatus.
  const handleCaptured = useCallback((params: Readonly<Record<string, string>>) => {
    const session = sessionRef.current;
    if (!session || !session.wasMock) return;
    const code = params.code;
    if (!code) return;

    setTokenStatus('Exchanging code for tokens…');
    (async () => {
      try {
        const tokens = await exchangeCodeForTokens(code, session.authorizeUrl, MOCK_CODE_VERIFIER);
        sessionRef.current = { ...session, idToken: tokens.idToken };
        setTokenStatus(`id_token acquired ${nowTime()} — ready to logout.`);
      } catch (error) {
        sessionRef.current = { ...session, idToken: null };
        setTokenStatus(`Token exchange failed: ${describe(error)}`);
      }
    })().catch(() => {});
  }, []);

  const logout = useCallback(() => {
    if (isLoggingOut) return;
    setIsLoggingOut(true);
    setLogoutMessage(null);
    setGatewayLogoutURL(null);

    (async () => {
      try {
        if (settings.useMockGateway) {
          const session = sessionRef.current;
          if (!session || !session.idToken) {
            setLogoutMessage(
              'No id_token yet — start a login (mock) and let the code exchange finish first.'
            );
            return;
          }
          await keycloakLogout(session.idToken, session.authorizeUrl);
          setLogoutMessage(`Logout successful ${nowTime()} — SSO session invalidated.`);
          sessionRef.current = { ...session, idToken: null };
          setTokenStatus(null);
        } else {
          const url = await gatewayLogout(settings.gatewayBaseURL);
          console.log('url ', url);
          
          setGatewayLogoutURL(url);
          setLogoutMessage(
            `Received logout URL ${nowTime()} — call it separately to complete logout.`
          );
        }
      } catch (error) {
        setLogoutMessage(`Logout failed: ${describe(error)}`);
      } finally {
        setIsLoggingOut(false);
      }
    })().catch(() => {});
  }, [isLoggingOut, settings.useMockGateway, settings.gatewayBaseURL]);

  return {
    tokenStatus,
    isLoggingOut,
    logoutMessage,
    gatewayLogoutURL,
    beginSession,
    handleCaptured,
    logout,
  };
}

function nowTime(): string {
  return new Date().toLocaleTimeString();
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
