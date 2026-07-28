# Security Policy

This project ships an authentication security core. Please report
vulnerabilities responsibly and do not open a public GitHub issue for
anything that could be exploitable.

## Reporting a vulnerability

Email **`<security-contact@your-domain>`** (placeholder — replace with a real
monitored address before publishing) with:

- A description of the vulnerability and its potential impact.
- Steps to reproduce (a minimal repro project or PoC, if possible).
- The affected package(s) and version(s) — `sea-core-ios`, `sea-react-native`,
  or the Keycloak theme in `themes/`.

We aim to acknowledge reports within **3 business days** and to provide a
remediation timeline within **10 business days** of confirming the issue.

## Scope

In scope:

- `packages/sea-core-ios` — the embedded-WebView auth core.
- `packages/sea-react-native` — the Fabric bridge.
- `themes/` — the Keycloak theme shipped alongside SEA.

Out of scope (see [bankerise_sea_specs-v1.0.md](bankerise_sea_specs-v1.0.md)
§3/§15/§16 for the reasoning):

- App Attest / device attestation — a host-app and API Gateway responsibility.
- TLS/certificate pinning — configured by the integrating app, not by SEA.
- The demo apps (`apps/demo-ios`, `apps/demo-rn`) are test harnesses, not
  production software; issues specific to them (e.g. hardcoded demo
  credentials, mock gateway behavior) are expected and not vulnerabilities.

## Supported versions

This project is pre-1.0. Security fixes land on `develop` and are released
under the latest `0.x` tag; there is no long-term-support branch yet.
