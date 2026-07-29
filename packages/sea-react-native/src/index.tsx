import * as React from 'react';
import NativeSecureAuthenticationView from './SecureAuthenticationViewNativeComponent';
import type {
  CapturedNativeEvent,
  ErrorNativeEvent,
  NativeAppearance,
} from './SecureAuthenticationViewNativeComponent';
import type { NativeSyntheticEvent } from 'react-native';

// SEAError taxonomy (spec §7.2) — crosses the bridge unchanged (§7.4).
export type SEAErrorCode =
  | 'network'
  | 'timeout'
  | 'cancelled'
  | 'invalid_authorize_url'
  | 'server_error'
  | 'webauthn_unavailable'
  | 'kill_switched';

export type SEAError = Readonly<{
  code: SEAErrorCode;
  message?: string;
}>;

export type SEAAppearance = Readonly<{
  headerBackground?: NativeAppearance['headerBackground'];
  headerText?: NativeAppearance['headerText'];
  accent?: NativeAppearance['accent'];
  closeIconTint?: NativeAppearance['closeIconTint'];
  cornerRadius?: number;
  // undefined -> live page title (contract §9).
  title?: string;
}>;

export type SecureAuthenticationViewProps = Readonly<{
  authorizeUrl: string;
  presentation?: 'sheet' | 'fullscreen';
  appearance?: SEAAppearance;
  allowedDomains?: ReadonlyArray<string>;
  timeoutMs?: number;
  callbackScheme?: string;
  allowedPorts?: ReadonlyArray<number>;
  maxUrlLengthBytes?: number;
  onCaptured?: (params: Readonly<Record<string, string>>) => void;
  onCancelled?: () => void;
  onError?: (error: SEAError) => void;
}>;

/**
 * Spec §7.1. A marshalling-only Fabric component: mount presents the
 * hardened embedded-WebView auth surface (or the §10.4 fallback) from
 * `sea-core-ios`; a terminal `onCaptured`/`onCancelled`/`onError` fires
 * exactly once, after which the host is expected to unmount this
 * component, which dismisses the presented surface (§7.2).
 */
export function SecureAuthenticationView(
  props: SecureAuthenticationViewProps
) {
  const { appearance, onCaptured, onCancelled, onError, ...rest } = props;

  const handleCaptured = React.useCallback(
    (event: NativeSyntheticEvent<CapturedNativeEvent>) => {
      if (!onCaptured) return;
      let params: Record<string, string> = {};
      try {
        params = JSON.parse(event.nativeEvent.paramsJson);
      } catch {
        // Malformed payload from the native side should never happen; fail
        // closed to an empty params object rather than throwing into RN's
        // event dispatch.
      }
      onCaptured(params);
    },
    [onCaptured]
  );

  const handleCancelled = React.useCallback(() => {
    onCancelled?.();
  }, [onCancelled]);

  const handleError = React.useCallback(
    (event: NativeSyntheticEvent<ErrorNativeEvent>) => {
      onError?.({
        code: event.nativeEvent.code as SEAErrorCode,
        message: event.nativeEvent.message,
      });
    },
    [onError]
  );

  return (
    <NativeSecureAuthenticationView
      {...rest}
      appearance={appearance as NativeAppearance}
      onCaptured={handleCaptured}
      onCancelled={handleCancelled}
      onError={handleError}
    />
  );
}

export default SecureAuthenticationView;

export {
  subscribeToTelemetry,
  copyToClipboard,
  purgeWebData,
} from './telemetry';
export type { SEATelemetryEvent } from './telemetry';
