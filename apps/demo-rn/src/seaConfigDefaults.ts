/**
 * Legacy re-export point retained so imports in settings.ts don't break.
 *
 * Security values are no longer loaded from JS or a native module at all:
 * `SecureAuthenticationView` does not accept them as props. They are owned
 * by the native platform config — `SEASecurityConfig.plist` on iOS (read by
 * `SEAEnvironment`) and `bankerise-sea.properties` on Android (read by
 * `SEAPropertiesLoader`) — so this function always throws.
 */
export function getSEAConfigDefaults(): never {
  throw new Error(
    'SEAConfigProvider native module was removed. Security values are owned by the platform config (SEASecurityConfig.plist / bankerise-sea.properties).'
  );
}
