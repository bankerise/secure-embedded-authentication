#!/usr/bin/env bash
# Install the mkcert local CA into the booted iOS Simulator's trust store.
#
# Scope note, deliberately: this touches the SIMULATOR keychain only. We do
# NOT run `mkcert -install`, which would add the CA to your macOS system trust
# store — a machine-wide change nobody asked for. The simulator is the only
# place that needs to trust this cert.
#
# To undo: erase the simulator (`xcrun simctl erase <udid>`).
set -euo pipefail

CAROOT="$(mkcert -CAROOT)"
ROOT_CA="${CAROOT}/rootCA.pem"

[[ -f "${ROOT_CA}" ]] || { echo "No mkcert CA at ${ROOT_CA}. Run infra/gen-certs.sh first." >&2; exit 1; }

if ! xcrun simctl list devices booted | grep -q '('; then
  echo "No booted simulator. Boot one first:" >&2
  echo "  xcrun simctl boot 'iPhone 17' && open -a Simulator" >&2
  exit 1
fi

xcrun simctl keychain booted add-root-cert "${ROOT_CA}"
echo "✓ mkcert CA trusted by the booted simulator."
echo "  https://localhost will now validate cleanly inside WKWebView,"
echo "  with SEA's TLS handling in its production configuration —"
echo "  no invalid-certificate acceptance path anywhere (§8.2)."
