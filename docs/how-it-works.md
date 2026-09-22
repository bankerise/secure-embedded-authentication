# How SEA works

This page explains what happens during a login and why it's safe, without
the formal detail. For the full specification and threat model, see
[design/specification.md](design/specification.md).

## The login flow

```
 Your app              Your backend              Identity provider (e.g. Keycloak)
    │                       │                                  │
    │ 1. "start login"      │                                  │
    ├──────────────────────►│                                  │
    │   authorize URL       │  builds the URL (state + PKCE)   │
    │◄──────────────────────┤                                  │
    │                                                          │
    │ 2. SEA opens the URL in a locked-down WebView            │
    ├─────────────────────────────────────────────────────────►│
    │         user signs in: password, passkey, OTP, …         │
    │◄─────────────────────────────────────────────────────────┤
    │   redirect to  myapp://callback?code=…&state=…           │
    │                                                          │
    │ 3. SEA catches the redirect inside the app               │
    │    and calls onCaptured({ code, state, … })              │
    │                       │                                  │
    │ 4. send code + state  │                                  │
    ├──────────────────────►│  exchanges the code for tokens   │
    │                       ├─────────────────────────────────►│
    │   your app session    │                                  │
    │◄──────────────────────┤                                  │
```

1. **Your backend creates the authorize URL.** It owns the OAuth client, the
   `state` and the PKCE verifier. The app only receives a URL to open.
2. **SEA shows the provider's login page** in a hardened WebView, presented as
   a native sheet or fullscreen screen. Everything the provider supports
   (MFA, passkeys, password reset, required actions) works without any app
   release.
3. **SEA captures the redirect.** When the provider redirects to your callback
   scheme, SEA intercepts it *before* it becomes a real network request or an
   OS-level deep link, closes the WebView, and gives you the raw parameters.
4. **Your backend finishes the job.** It exchanges the code for tokens, the
   same as any standard OAuth flow. SEA never reads, stores or exchanges tokens.

Exactly one of `onCaptured`, `onCancelled` or `onError` fires, exactly once,
per login attempt.

## What keeps it safe

| Risk | What SEA does |
|---|---|
| A tampered or phishing authorize URL | The URL must be `https`, on a standard port, and on a domain in your allowlist, or nothing loads. Plain `http` can be enabled for local development only |
| The page navigating somewhere unexpected | Every navigation is checked against the same allowlist. Anything else is blocked, never silently followed |
| Another app hijacking the callback | The callback is captured inside the WebView, in your process. It never goes through the OS deep-link system (except in the system-browser fallback) |
| The host app reading credentials | The WebView's cookies, DOM and JavaScript are never exposed to app code. There is no JavaScript bridge |
| Screenshots or screen recordings | Capture is detected and reported, and the surface can be protected |
| Leftover web data | Web data is scoped to SEA and can be wiped on logout with `purgeWebData` |

The allowlist and callback scheme come from a config file **bundled in your
own signed app** (`SEASecurityConfig.plist` on iOS, `bankerise-sea.properties`
or `SEAConfig` on Android). Values passed at runtime can only *narrow* that
list, never widen it. If the config is missing or invalid, SEA fails
closed: every navigation is blocked.

## Passkeys and the system-browser fallback

Passkeys (WebAuthn) run inside the embedded WebView. On iOS this needs an
[Associated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
entitlement for your identity provider's domain. On Android it needs a
[Digital Asset Links](https://developer.android.com/identity/sign-in/credential-manager#add-support-dal)
file.

If a device can't run the passkey ceremony inside a WebView, SEA
automatically switches the whole login to the platform's secure system
browser (`ASWebAuthenticationSession` on iOS, Auth Tab / Custom Tabs on
Android). You get the same callbacks either way. You can also force this mode
with `authMode = nativeBrowser`.

## What SEA doesn't do

These are deliberately left to your app and backend:

- Building the authorize URL and exchanging the code for tokens
- Storing tokens and managing the app session
- Certificate pinning and device attestation (App Attest / Play Integrity)
