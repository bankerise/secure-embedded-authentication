# SEA demo — Android

A native Android (Jetpack Compose) app for trying `sea-core-android` end to
end. It builds the SDK from source (`packages/sea-core-android` is included as
a Gradle module), so SDK changes show up immediately.

Open this directory in Android Studio and run the `app` configuration, or:

```bash
./gradlew :app:installDebug
```

The app has Config, Result and Telemetry screens, and a mock-gateway mode
that needs no backend. See [docs/demo-apps.md](../../docs/demo-apps.md) for
the local Keycloak setup.
