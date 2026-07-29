import React from 'react';
import {
  ActivityIndicator,
  Button,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import type { Settings } from '../settings';

type Props = {
  settings: Settings;
  onChangeSettings: (patch: Partial<Settings>) => void;
  isRunning: boolean;
  lastStartError: string | null;
  onStartLogin: () => void;
  onPurgeWebData: () => void;
  purgeMessage: string | null;
  useMockGateway: boolean;
  isLoggingOut: boolean;
  onLogout: () => void;
  tokenStatus: string | null;
  logoutMessage: string | null;
  gatewayLogoutURL: string | null;
};

const MIN_TIMEOUT_MS = 5_000;
const MAX_TIMEOUT_MS = 600_000;
const TIMEOUT_STEP_MS = 5_000;

// UI-only merge of SEAConfig's two independent knobs (presentation,
// authMode) into a single 3-way picker, so a tester can reach the §10.4
// fallback (ASWebAuthenticationSession) without a separate control.
// 'browser' means authMode: 'nativeBrowser' — presentation is irrelevant on
// that path (the fallback runner ignores it) but a value is still needed on
// Settings, so it's left unchanged.
type RendererMode = 'sheet' | 'fullscreen' | 'browser';

const RENDERER_LABEL: Record<RendererMode, string> = {
  sheet: 'Sheet',
  fullscreen: 'Fullscreen',
  browser: 'Browser',
};

const RENDERER_PATCH: Record<RendererMode, Partial<Settings>> = {
  sheet: { presentation: 'sheet', authMode: 'embedded' },
  fullscreen: { presentation: 'fullscreen', authMode: 'embedded' },
  browser: { authMode: 'nativeBrowser' },
};

function rendererMode(settings: Settings): RendererMode {
  return settings.authMode === 'nativeBrowser' ? 'browser' : settings.presentation;
}

/** Mirrors apps/demo-ios/Sources/Views/ConfigView.swift (spec §7, §11.3). */
export function ConfigScreen({
  settings,
  onChangeSettings,
  isRunning,
  lastStartError,
  onStartLogin,
  onPurgeWebData,
  purgeMessage,
  useMockGateway,
  isLoggingOut,
  onLogout,
  tokenStatus,
  logoutMessage,
  gatewayLogoutURL,
}: Props): React.JSX.Element {
  return (
    <ScrollView style={styles.root} contentContainerStyle={styles.content}>
      <Section title="Gateway">
        <Field label="Gateway base URL">
          <TextInput
            style={styles.input}
            value={settings.gatewayBaseURL}
            onChangeText={(v) => onChangeSettings({ gatewayBaseURL: v })}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
          />
        </Field>
        <Field label="App version key">
          <TextInput
            style={[styles.input, styles.mono]}
            value={settings.appVersionKey}
            onChangeText={(v) => onChangeSettings({ appVersionKey: v })}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </Field>
        <View style={styles.row}>
          <Text style={styles.label}>Use mock gateway</Text>
          <Switch
            value={settings.useMockGateway}
            onValueChange={(v) => onChangeSettings({ useMockGateway: v })}
          />
        </View>
        {settings.useMockGateway && (
          <Field label="Mock redirectUrl">
            <TextInput
              style={[styles.input, styles.mono]}
              value={settings.mockRedirectURL}
              onChangeText={(v) => onChangeSettings({ mockRedirectURL: v })}
              autoCapitalize="none"
              autoCorrect={false}
              multiline
            />
          </Field>
        )}
      </Section>

      <Section title="SEAConfig">
        <Field label="Callback scheme">
          <TextInput
            style={[styles.input, styles.mono]}
            value={settings.callbackScheme}
            onChangeText={(v) => onChangeSettings({ callbackScheme: v })}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </Field>
        <Field label="Allowed domains (comma list)">
          <TextInput
            style={styles.input}
            value={settings.allowedDomains}
            onChangeText={(v) => onChangeSettings({ allowedDomains: v })}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </Field>
        <Field label="Allowed ports (comma list)">
          <TextInput
            style={[styles.input, styles.mono]}
            value={settings.allowedPorts}
            onChangeText={(v) => onChangeSettings({ allowedPorts: v })}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="numeric"
          />
        </Field>
        <Field label="Max URL length (bytes)">
          <TextInput
            style={[styles.input, styles.mono]}
            value={String(settings.maxUrlLengthBytes)}
            onChangeText={(v) => onChangeSettings({ maxUrlLengthBytes: parseInt(v, 10) || 2048 })}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="numeric"
          />
        </Field>
        <View style={styles.row}>
          <Text style={styles.label}>Presentation</Text>
          <View style={styles.segmented}>
            {(['sheet', 'fullscreen', 'browser'] as const).map((option) => (
              <Text
                key={option}
                onPress={() => onChangeSettings(RENDERER_PATCH[option])}
                style={[
                  styles.segment,
                  rendererMode(settings) === option && styles.segmentActive,
                ]}
              >
                {RENDERER_LABEL[option]}
              </Text>
            ))}
          </View>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Timeout: {settings.timeoutMs} ms</Text>
          <View style={styles.stepper}>
            <Text
              style={styles.stepperButton}
              onPress={() =>
                onChangeSettings({
                  timeoutMs: Math.max(MIN_TIMEOUT_MS, settings.timeoutMs - TIMEOUT_STEP_MS),
                })
              }
            >
              −
            </Text>
            <Text
              style={styles.stepperButton}
              onPress={() =>
                onChangeSettings({
                  timeoutMs: Math.min(MAX_TIMEOUT_MS, settings.timeoutMs + TIMEOUT_STEP_MS),
                })
              }
            >
              +
            </Text>
          </View>
        </View>
      </Section>

      <Section>
        {isRunning ? (
          <View style={styles.row}>
            <ActivityIndicator />
            <Text style={styles.label}>Starting…</Text>
          </View>
        ) : (
          <Button title="Start login" onPress={onStartLogin} />
        )}
        {lastStartError && <Text style={styles.error}>{lastStartError}</Text>}
      </Section>

      <Section title="Logout">
        {isLoggingOut ? (
          <View style={styles.row}>
            <ActivityIndicator />
            <Text style={styles.label}>Logging out…</Text>
          </View>
        ) : (
          <Button title="Logout" onPress={onLogout} />
        )}
        {tokenStatus && <Text style={styles.hint}>{tokenStatus}</Text>}
        {logoutMessage && <Text style={styles.hint}>{logoutMessage}</Text>}
        {gatewayLogoutURL && (
          <Text style={[styles.hint, styles.mono]} selectable>
            {gatewayLogoutURL}
          </Text>
        )}
        <Text style={styles.footer}>
          {useMockGateway
            ? 'Mock: RP-initiated logout straight to Keycloak using the id_token from the last login (invalidates the SSO session server-side).'
            : 'Real: POST /gw/logout returns a Keycloak logout URL enriched with id_token_hint, to be called separately from the app.'}
        </Text>
      </Section>

      <Section title="Session data">
        <Button title="Purge web data" color="#c0392b" onPress={onPurgeWebData} />
        {purgeMessage && <Text style={styles.hint}>{purgeMessage}</Text>}
      </Section>
    </ScrollView>
  );
}

function Section({
  title,
  children,
}: {
  title?: string;
  children: React.ReactNode;
}): React.JSX.Element {
  return (
    <View style={styles.section}>
      {title && <Text style={styles.sectionTitle}>{title}</Text>}
      {children}
    </View>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}): React.JSX.Element {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 16 },
  section: {
    gap: 10,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#c7c7cc',
    borderRadius: 10,
    padding: 12,
  },
  sectionTitle: { fontSize: 13, fontWeight: '600', color: '#6d6d72', textTransform: 'uppercase' },
  field: { gap: 4 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  label: { fontSize: 15 },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#c7c7cc',
    borderRadius: 6,
    padding: 8,
    fontSize: 14,
  },
  mono: { fontFamily: 'Menlo', fontSize: 11 },
  segmented: { flexDirection: 'row' },
  segment: {
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#007aff',
    color: '#007aff',
    fontSize: 13,
  },
  segmentActive: { backgroundColor: '#007aff', color: 'white' },
  stepper: { flexDirection: 'row', gap: 12 },
  stepperButton: {
    fontSize: 20,
    width: 32,
    height: 32,
    textAlign: 'center',
    lineHeight: 30,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#c7c7cc',
    borderRadius: 6,
  },
  error: { color: '#c0392b', fontSize: 12 },
  hint: { color: '#6d6d72', fontSize: 12 },
  footer: { color: '#8e8e93', fontSize: 11, marginTop: 4 },
});
