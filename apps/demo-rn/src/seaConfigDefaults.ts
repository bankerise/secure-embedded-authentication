import { NativeModules, Platform } from 'react-native';

type SEAConfigDefaults = {
  callbackScheme: string;
  authDomains: string;
  allowedPorts: string;
  maxUrlLengthBytes: number;
};

const LINKING_ERROR =
  `The package 'sea-config-provider' doesn't seem to be linked. Make sure:\n\n` +
  Platform.select({ ios: "Run 'pod install' in the ios/ directory", default: '' }) +
  '\n- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go';

/**
 * Reads `bankerise-sea.properties` from the Android assets via a
 * NativeModule. Returns fallback defaults if the module is unavailable
 * (e.g. on iOS or during tests).
 */
export function getSEAConfigDefaults(): SEAConfigDefaults {
  const { SEAConfigProvider } = NativeModules;
  if (!SEAConfigProvider) {
    throw new Error(LINKING_ERROR);
  }
  return SEAConfigProvider.getConfig() as SEAConfigDefaults;
}
