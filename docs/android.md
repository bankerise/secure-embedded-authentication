# Android guide

Add SEA's secure login screen to a native Android app.

**Requirements:** minSdk 24 (Android 7.0), compileSdk 35+, Kotlin, JDK 17.

## 1. Install

SEA is on Maven Central. Make sure `mavenCentral()` is in your repositories
(it is by default), then add the dependency:

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("com.bankerise:sea-core-android:0.0.1")
}
```

The library's manifest is merged into your app automatically. It declares the
`INTERNET` permission and the activity that hosts the login screen, so you
don't need to add anything to your own manifest.

## 2. Start a login

Get an authorize URL from your backend, then:

```kotlin
import com.bankerise.sea.core.*

val config = SEAConfig(
    authorizeUrl = Uri.parse(authorizeUrl),
    callbackScheme = "myapp",                     // scheme of your redirect URI
    allowedDomains = listOf("auth.example.com"),  // domains the WebView may load
    presentation = SEAPresentation.SHEET,         // or FULLSCREEN
)

SEASession.start(
    activity = this,
    config = config,
    callbacks = SEASession.Callbacks(
        onCaptured = { params ->
            // params.code, params.state, params.raw…
            // Send them to your backend to exchange for tokens.
        },
        onCancelled = {
            // The user closed the login screen.
        },
        onError = { error ->
            // See "Errors" below.
        },
    ),
)
```

All SEA APIs must be called on the main thread, and all callbacks arrive on
the main thread.

> Keep `callbackScheme` and `allowedDomains` as constants in your app (or in
> the `bankerise-sea.properties` asset below), never values from a server
> response. They are what make the login screen safe.

### Optional: config file

Instead of hard-coding the values, you can put them in
`src/main/assets/bankerise-sea.properties`:

```properties
callbackScheme=myapp
authDomains=auth.example.com
# Optional. Defaults to https only
allowedSchemes=https
# Optional. Defaults to -1,443 (-1 = no explicit port)
allowedPorts=-1,443
```

Then load the file and add the authorize URL:

```kotlin
val config = SEAPropertiesLoader.loadConfig(context)
    .copy(authorizeUrl = Uri.parse(authorizeUrl))
```

If the file is missing or incomplete, SEA **fails closed**: every navigation
is blocked. It never crashes.

## Customize the look

```kotlin
val appearance = SEAAppearance.default.copy(
    title = "Sign in",           // null shows the page's own title
    accent = 0xFF3D8BFF.toInt(),
    cornerRadius = 16f,          // dp
)

val config = SEAConfig(/* … */, appearance = appearance)
```

## Other options

| `SEAConfig` parameter | Default | What it does |
|---|---|---|
| `presentation` | `SHEET` | `SHEET` or `FULLSCREEN` |
| `timeoutMs` | `120_000` | Gives up with `Timeout` after this long |
| `capturePolicy` | `WARN` | What happens on screen capture: `LOG`, `WARN` or `BLOCK_INPUT` |
| `authMode` | `EMBEDDED` | `NATIVE_BROWSER` always uses the system browser (Auth Tab / Custom Tabs) |
| `allowedSchemes` | `https` | URL schemes the WebView may load |
| `allowedPorts` | `-1, 443` | Ports the authorize URL may use. `-1` means no explicit port |

## Local development over `http`

SEA only loads `https` by default. If your local identity provider has no
TLS, you can allow plain `http` in **debug builds only**:

1. Allow the scheme, and the port if it isn't the default. With the config
   file, put this in `src/debug/assets/bankerise-sea.properties` so it
   never reaches a release build:

   ```properties
   callbackScheme=myapp
   authDomains=10.0.2.2
   allowedSchemes=https,http
   allowedPorts=-1,443,8080
   ```

   In code, the equivalent is
   `SEAConfig(..., allowedSchemes = setOf("https", "http"), allowedPorts = setOf(-1, 443, 8080))`.

2. Let the app use cleartext for that host. Add a debug-only
   `src/debug/res/xml/network_security_config.xml`:

   ```xml
   <network-security-config>
       <domain-config cleartextTrafficPermitted="true">
           <domain includeSubdomains="false">10.0.2.2</domain>
       </domain-config>
   </network-security-config>
   ```

   and reference it from your manifest with
   `android:networkSecurityConfig="@xml/network_security_config"`.

The emulator reaches your computer at `10.0.2.2`, not `localhost`.

> Never ship `http` in a release build. Keeping the properties file and
> network security config under `src/debug/` ensures the release app stays
> `https`-only.

## Passkeys

To use passkeys inside the login screen, publish a
[Digital Asset Links](https://developer.android.com/identity/sign-in/credential-manager#add-support-dal)
file (`/.well-known/assetlinks.json`) on your identity provider's domain. It
must list your app's package name and all of its signing certificates,
including the Play App Signing key.

## Logout

Clear SEA's web data (cookies, SSO session) when the user logs out:

```kotlin
SEASession.purgeWebData(context) {
    // done
}
```

Also end the session on your identity provider (RP-initiated logout) from
your backend.

## Telemetry

Implement `SEATelemetrySink` to receive lifecycle events such as
`AUTH_PAGE_LOADED`, `AUTH_NAV_BLOCKED` and `AUTH_COMPLETED`. Events never
contain credentials, codes or full URLs.

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SEASession.telemetrySink = object : SEATelemetrySink {
            override fun record(event: SEAEvent) = Log.d("SEA", event.toString())
        }
    }
}
```

## Errors

| `SEAError` | Meaning |
|---|---|
| `InvalidAuthorizeUrl(reason)` | The URL's scheme or port isn't allowed (`https` on the default port by default), isn't on an allowed domain, or is malformed. Nothing was loaded |
| `Network(underlying)` | No connectivity, DNS or TLS failure |
| `ServerError(statusCode)` | The login page returned an HTTP 5xx |
| `Timeout` | The session exceeded `timeoutMs` |
| `WebauthnUnavailable` | The system-browser fallback couldn't start |

## Known limitation

In `NATIVE_BROWSER` mode, and when SEA falls back to the system browser
automatically, the redirect back into the app currently uses the fixed scheme
`sea-default-callback://callback`. Register that redirect URI on your OAuth
client if you rely on this mode. The default embedded mode works with any
scheme.
