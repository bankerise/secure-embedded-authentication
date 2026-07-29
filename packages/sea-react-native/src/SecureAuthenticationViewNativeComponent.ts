import type { ViewProps, ColorValue } from 'react-native';
import type {
  DirectEventHandler,
  Int32,
  Double,
  WithDefault,
} from 'react-native/Libraries/Types/CodegenTypesNamespace';
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';

// Mirrors SEAAppearance (packages/sea-core-ios/Sources/SEACore/SEAAppearance.swift).
// Colors and text only (spec §18.1) — never layout.
export type NativeAppearance = Readonly<{
  headerBackground?: ColorValue;
  headerText?: ColorValue;
  accent?: ColorValue;
  closeIconTint?: ColorValue;
  cornerRadius?: Double;
  // Empty string means "unset" -> native falls back to the live page title
  // (contract §9), since Fabric's nested object props don't carry a plain
  // optional the way a top-level prop can.
  title?: WithDefault<string, ''>;
}>;

// SEACallbackParams.raw (packages/sea-core-ios/Sources/SEACore/SEACallbackParams.swift)
// is an arbitrary String:String map, which Fabric's strictly-typed event
// schema can't express directly (no index-signature/dynamic-key objects).
// It crosses the bridge as a JSON string here and is parsed back into a
// plain object by the JS wrapper (src/index.tsx) before reaching
// `onCaptured` — mechanical marshalling only (spec §7.4), not a semantic
// interpretation of the params.
export type CapturedNativeEvent = Readonly<{
  paramsJson: string;
}>;

export type CancelledNativeEvent = Readonly<{}>;

// SEAError taxonomy (packages/sea-core-ios/Sources/SEACore/SEAError.swift),
// crossed unchanged per spec §7.4.
export type ErrorNativeEvent = Readonly<{
  code: string;
  message?: string;
}>;

export interface NativeProps extends ViewProps {
  // Gateway-issued authorize URL (spec §6.1); origin-validated by the core
  // (§6.2). Required — there is no meaningful default.
  authorizeUrl: string;

  presentation?: WithDefault<'sheet' | 'fullscreen', 'sheet'>;
  appearance?: NativeAppearance;

  // Host-supplied narrowing allowlist (spec §7.1/§7.3) — intersected with
  // the native-compiled allowlist, never widens it.
  allowedDomains?: ReadonlyArray<string>;

  timeoutMs?: Int32;

  // Custom scheme the callback redirect uses (§6.3).
  callbackScheme?: string;

  // Allowed ports for the authorize URL (§6.2). -1 = unset (standard HTTPS).
  allowedPorts?: ReadonlyArray<Int32>;

  // Maximum byte length of the authorize URL string (§6.2).
  maxUrlLengthBytes?: Int32;

  onCaptured?: DirectEventHandler<CapturedNativeEvent>;
  onCancelled?: DirectEventHandler<CancelledNativeEvent>;
  onError?: DirectEventHandler<ErrorNativeEvent>;
}

export default codegenNativeComponent<NativeProps>('SeaReactNativeView');
