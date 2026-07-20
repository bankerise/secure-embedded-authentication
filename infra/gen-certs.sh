#!/usr/bin/env bash
# Generate the local dev TLS certificate for the Keycloak terminator.
# Certs and keys are gitignored — every developer generates their own.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p tls

mkcert -cert-file tls/sea-dev.pem -key-file tls/sea-dev-key.pem \
       localhost 127.0.0.1 ::1

echo
echo "✓ Certificate written to infra/tls/"
echo "  Next: ./trust-ca-simulator.sh   (with a simulator booted)"
