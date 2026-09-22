# Security policy

SEA is an authentication component, so we take security reports seriously.
Thank you for helping keep it and its users safe.

## Reporting a vulnerability

**Please don't open a public issue, discussion or pull request for security
problems.**

Report it privately through
[GitHub's private vulnerability reporting](https://github.com/bankerise/secure-embedded-authentication/security/advisories/new).
Please include:

- What the issue is and what an attacker could do with it
- Steps to reproduce (a small sample project or proof of concept helps a lot)
- Affected package(s) and version(s)

We aim to acknowledge reports within **3 business days** and to share a fix
timeline within **10 business days** of confirming the issue. We'll credit
you in the advisory unless you prefer otherwise.

## Scope

In scope:

- `packages/sea-core-ios`, the iOS SDK
- `packages/sea-core-android`, the Android SDK
- `packages/sea-react-native`, the React Native wrapper
- `themes/`, the Keycloak login theme

Out of scope:

- Certificate pinning and device attestation (App Attest, Play Integrity).
  These are the integrating app's and backend's responsibility by design.
- The demo apps and `infra/`. They are local test tools with intentionally
  hard-coded credentials and relaxed settings.

## Supported versions

SEA is pre-1.0. Fixes are released in the latest `0.0.x` version of each
package. Older versions don't receive backports.
