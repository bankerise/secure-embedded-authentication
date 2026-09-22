# Design documents

These are the detailed engineering documents behind SEA. You don't need them
to *use* SEA (start with the [guides](../../README.md#documentation)), but
they explain every decision in depth.

| Document | What's in it |
|---|---|
| [specification.md](specification.md) | The full technical spec: threat model, design rationale, platform details. Code comments like `§6.2` point to its sections |
| [api-contract-ios.md](api-contract-ios.md) | The iOS SDK's public API contract |
| [api-contract-react-native.md](api-contract-react-native.md) | The React Native wrapper's API contract |
| [android-ios-parity.md](android-ios-parity.md) | How the Android SDK maps to the iOS SDK |

Some of these documents mention Bankerise's own backend (the "API Gateway"
and "Bankerise Mobile SDK"). In your app, that role is played by your own
backend.
