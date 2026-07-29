/**
 * demo-rn — bridge validation harness for sea-react-native (spec §4.4).
 * Config/Result/Telemetry tabs mirror apps/demo-ios's ConfigView/ResultsView/
 * TelemetryConsoleView; the Fuzz view is intentionally not ported — it's a
 * SEACore-internal Swift-only fuzzing harness, not part of the bridge
 * surface sea-react-native exposes. No navigation library (three tabs isn't
 * worth the dependency) and no persisted settings (in-memory only) — see
 * src/settings.ts and src/deviceIdentity.ts for the specifics.
 */
import React, { useCallback, useState } from 'react';
import { SafeAreaView, StyleSheet } from 'react-native';
import { purgeWebData, SecureAuthenticationView } from 'sea-react-native';
import { startAuthorization as startMockAuthorization } from './src/mockGateway';
import { getCurrentUser, startAuthorization as startRealAuthorization } from './src/gateway';
import { allowedDomainsArray, DEFAULT_SETTINGS, type Settings } from './src/settings';
import type { Result } from './src/types';
import { useSessionLogout } from './src/useSessionLogout';
import { ConfigScreen } from './src/screens/ConfigScreen';
import { ResultScreen } from './src/screens/ResultScreen';
import { TelemetryScreen } from './src/screens/TelemetryScreen';
import { TabBar, type TabKey } from './src/TabBar';

function parsePorts(portsStr: string): number[] {
  return portsStr
    .split(',')
    .map((s) => parseInt(s.trim(), 10))
    .filter((n) => !isNaN(n));
}

function App(): React.JSX.Element {
  const [activeTab, setActiveTab] = useState<TabKey>('config');
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [isRunning, setIsRunning] = useState(false);
  const [lastStartError, setLastStartError] = useState<string | null>(null);
  const [purgeMessage, setPurgeMessage] = useState<string | null>(null);
  const [authorizeUrl, setAuthorizeUrl] = useState<string | null>(null);
  const [result, setResult] = useState<Result>({ kind: 'idle' });
  const session = useSessionLogout(settings);

  const onChangeSettings = useCallback((patch: Partial<Settings>) => {
    setSettings((prev) => ({ ...prev, ...patch }));
  }, []);

  const startLogin = useCallback(async () => {
    if (isRunning) return;
    setIsRunning(true);
    setLastStartError(null);
    try {
      const start = settings.useMockGateway
        ? await startMockAuthorization(settings.mockRedirectURL)
        : await startRealAuthorization(settings.gatewayBaseURL, settings.appVersionKey);
        
      setAuthorizeUrl(start.authorizeUrl);
      // Remember what Logout needs from this session (authorize URL + mock flag).
      session.beginSession(start.authorizeUrl, settings.useMockGateway);
    } catch (error) {
      console.log('error ', error);
      
      setLastStartError(error instanceof Error ? error.message : String(error));
    } finally {
      setIsRunning(false);
    }
  }, [isRunning, settings, session]);

  const dismiss = useCallback(() => {
    console.log('dismiss');
    setAuthorizeUrl(null)
    getCurrentUser();
  }, []);

  const onPurgeWebData = useCallback(() => {
    setPurgeMessage('Purging…');
    purgeWebData().then(() => {
      setPurgeMessage(`Purged at ${new Date().toLocaleTimeString()}`);
    });
  }, []);
  
  return (
    <SafeAreaView style={styles.root}>
      {activeTab === 'config' && (
        <ConfigScreen
          settings={settings}
          onChangeSettings={onChangeSettings}
          isRunning={isRunning}
          lastStartError={lastStartError}
          onStartLogin={startLogin}
          onPurgeWebData={onPurgeWebData}
          purgeMessage={purgeMessage}
          useMockGateway={settings.useMockGateway}
          isLoggingOut={session.isLoggingOut}
          onLogout={session.logout}
          tokenStatus={session.tokenStatus}
          logoutMessage={session.logoutMessage}
          gatewayLogoutURL={session.gatewayLogoutURL}
        />
      )}
      {activeTab === 'result' && (
        <ResultScreen result={result} onClear={() => setResult({ kind: 'idle' })} />
      )}
      {activeTab === 'telemetry' && <TelemetryScreen />}

      <TabBar active={activeTab} onChange={setActiveTab} />

      {authorizeUrl !== null && (
        <SecureAuthenticationView
          authorizeUrl={authorizeUrl}
          presentation={settings.presentation}
          allowedDomains={allowedDomainsArray(settings)}
          timeoutMs={settings.timeoutMs}
          callbackScheme={settings.callbackScheme}
          allowedPorts={parsePorts(settings.allowedPorts)}
          maxUrlLengthBytes={settings.maxUrlLengthBytes}
          onCaptured={(params) => {
            setResult({ kind: 'captured', params, at: Date.now() });
            // Mock path only: exchange the code so Logout has an id_token_hint.
            session.handleCaptured(params);
            dismiss();
          }}
          onCancelled={() => {
            console.log('onCancelled ');
            setResult({ kind: 'cancelled', at: Date.now() });
            dismiss();
          }}
          onError={(error) => {
            console.log('onError ', error);
            setResult({ kind: 'error', error, at: Date.now() });
            dismiss();
          }}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});

export default App;
