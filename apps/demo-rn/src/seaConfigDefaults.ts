/**
 * SEAConfigDefaults were previously loaded from a `SEAConfigProvider`
 * NativeModule. As of the _prop-driven_ refactor (spec §4.5, §7.2) every
 * sensitive value is passed as a runtime prop from the settings UI —
 * nothing is compiled in.
 *
 * This file is kept as a re-export point so imports in settings.ts don't
 * break, but the function always returns fallback values (caller must handle
 * via the catch block in settings.ts's buildDefaults).
 */
export function getSEAConfigDefaults(): never {
  throw new Error(
    'SEAConfigProvider native module was removed. All values must be supplied via SEAConfig props at session time.'
  );
}
