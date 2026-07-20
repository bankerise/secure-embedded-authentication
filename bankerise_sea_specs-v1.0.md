# Bankerise Secure Embedded Authentication (SEA)

## Technical Specification — v1.0

| | |
|---|---|
| **Status** | Draft for review |
| **Version** | 1.0 |
| **Date** | 2026-07-20 |
| **Audience** | Bankerise platform engineering, mobile teams, security review, bank-side auditors |
| **Applies to** | Bankerise mobile apps (React Native, iOS + Android) authenticating against Keycloak |

---

## 1. Executive Summary

### 1.1 Purpose

This specification defines the Secure Embedded Authentication (SEA) component: a hardened, embedded WebView surface through which Bankerise mobile applications execute the OAuth 2.0 Authorization Code flow (with PKCE) against the bank's Keycloak identity provider.

### 1.2 Problem Statement

Bankerise currently performs mobile login through an in-app system browser (SFSafariViewController / Chrome Custom Tabs). This is standards-compliant but produces a visibly non-native experience: browser chrome, address bar, a perceptible context switch, and inconsistent theming. For a flagship banking app, the login screen is the front door; it must feel like part of the app.

### 1.3 Design Philosophy

1. **First-party trust boundary.** The bank owns the app, the Keycloak realm, and the IdP domain. The classical argument against embedded WebViews — that a third-party app could observe user credentials — does not apply in the same way. We nevertheless treat the WebView as a semi-trusted surface and apply compensating controls (§3, §16).
2. **Keycloak stays authoritative.** All authentication logic (credential validation, MFA orchestration, passkey ceremonies, password reset, brokering) lives in Keycloak. The mobile layer renders, isolates, and observes — it never re-implements authentication.
3. **The native/web seam is the security perimeter.** The single most sensitive interface in this design is the handoff of the authorization code from the WebView to native code (§6). It is specified exhaustively and everything else is forbidden by default (§13).
4. **Escape hatches are mandatory.** Embedded WebView authentication depends on OS behavior that changes across releases. Every deployment ships with a remotely-controllable fallback to system-browser authentication (§21).

### 1.4 Why Embedded Authentication Instead of Browser Redirects

- Full control of chrome: no address bar, no browser UI, native header with close/back.
- Seamless theming: Keycloak mobile theme + native transitions produce a login that is indistinguishable from a native screen.
- Deterministic lifecycle: native code controls presentation, dismissal, timeout, and error states.
- Industry precedent: Binance, Revolut, and the majority of tier-1 banking apps use embedded WebView login with a bank-owned IdP.

The trade-offs of this decision, and why they are acceptable, are recorded formally in §3.

---

## 2. Goals and Non-Goals

### 2.1 Goals

- G1. Authorization Code + PKCE login against Keycloak inside an embedded, hardened WebView, on iOS (WKWebView) and Android (WebView), surfaced to React Native as a single component.
- G2. **Passkeys (WebAuthn) as a first-class v1 authentication method**, executed inside the embedded WebView where platform support allows, with a specified fallback ceremony path (§10).
- G3. Persistent Keycloak SSO session across app restarts via a persistent, protected cookie store (§11), producing near-silent re-authentication.
- G4. Support for Keycloak-brokered **third-party web-based IdPs** rendered within the embedded flow, with a per-IdP embed/external policy (§12.4).
- G5. Full support for Keycloak-driven MFA, required actions, and password reset without mobile releases.
- G6. Binance-grade UX: native header, no browser affordances, first-frame-fast (§18, §22).
- G7. Auditable security posture mapped to OWASP MASVS and the OAuth 2.0 Security BCP, with explicit documentation of the RFC 8252 deviation (§3).

### 2.2 Non-Goals

- Native credential forms (Resource Owner Password Credentials / Direct Access Grants). ROPC is removed in OAuth 2.1, incompatible with passkeys/MFA, and duplicates IdP logic. Never.
- App2app authentication with national eID schemes (UAE Pass, PACI, etc.). Out of scope for v1; the architecture leaves room for it (§12.4, §28).
- Generic in-app browsing. SEA renders exactly one origin family (the auth domain plus allowlisted broker domains) and nothing else.
- SSO sharing with the device's system browser. Explicitly not a goal; the SSO session is app-scoped (§11.1).
- Offline authentication.

### 2.3 Explicitly Unsupported Approaches

| Approach | Why rejected |
|---|---|
| JavaScript injection into auth pages | Violates the boundary model (§13); indistinguishable from an attack in audit |
| Reading/manipulating DOM of auth pages | Same |
| Token exchange inside the WebView / JS | Tokens must never transit the web layer |
| Custom-scheme-only redirect capture without native interception | Interceptable by other apps on some platforms; we intercept in the navigation delegate instead (§6) |
| Storing tokens in cookies/localStorage | Tokens live in Keychain / Android Keystore-encrypted storage only |

---

## 3. Decision Record — Deviation from RFC 8252

> This section exists because every competent security review of this design will open with "RFC 8252 says don't do this." The answer must be in the document, not improvised in the meeting.

### 3.1 What the standards say

RFC 8252 (OAuth 2.0 for Native Apps) and the OAuth 2.0 Security Best Current Practice recommend that native apps use an **external user-agent** (system browser or in-app browser tab such as ASWebAuthenticationSession / Custom Tabs) rather than an embedded WebView. Keycloak's own documentation follows this recommendation. The stated reasons:

1. The host app can observe or capture user credentials entered in an embedded WebView.
2. Embedded WebViews do not share session state with the system browser, breaking SSO.
3. Habituating users to enter credentials into non-browser surfaces increases phishing susceptibility.
4. Some identity providers refuse embedded user-agents outright.

### 3.2 Why the deviation is acceptable here

1. **Reason (1) assumes an adversarial client.** SEA is a first-party component: the party that could theoretically capture credentials (the bank's app) is the same party that receives them legitimately (the bank's IdP). The residual risk is a *compromised* app binary, which is addressed by app attestation (§16) — a control that browser-redirect flows do not have either.
2. **Reason (2) is a non-goal.** We do not want browser-shared SSO for a banking app; the app-scoped persistent session (§11) is deliberate.
3. **Reason (3) is mitigated structurally**, not cosmetically: device integrity attestation means a fake app presenting a fake login screen cannot complete a token exchange (§16), and the observability pipeline (§20) detects anomalous auth funnels.
4. **Reason (4) is handled per-IdP** via the broker embed/external policy (§12.4) and the global kill switch (§21).

### 3.3 Alternatives considered

| Alternative | Verdict |
|---|---|
| ASWebAuthenticationSession / Custom Tabs (status quo) | Standards-ideal; rejected on UX grounds (browser chrome, context switch). Retained as the **fallback mode** (§21) and as the passkey fallback ceremony path (§10.4). |
| `prefersEphemeralWebBrowserSession` + heavy theming of system sheet | Still shows browser chrome; does not meet G6. |
| Native login UI + Direct Access Grants | Rejected outright (§2.2). |
| Fully native OIDC ceremony via AppAuth + custom Keycloak REST | Reimplements Keycloak flows in mobile; breaks G5; unmaintainable across MFA/passkey/required-action evolution. |

### 3.4 Compensating controls summary

Embedded WebView (this spec) + navigation allowlisting (§7.3) + native-only code handoff (§6) + zero JS injection (§13) + app attestation gating token issuance (§16) + TLS pinning policy (§15) + screen security (§17) + remote kill switch (§21) + auth-funnel observability (§20).

---

## 4. High-Level Architecture

```
                    Bankerise Mobile App
                           |
                    React Native Layer
              <SecureAuthenticationView/>
                           |
              Secure Authentication Component
              (native module, per platform)
                           |
          +----------------+----------------+
          |                                 |
      iOS Native                       Android Native
      WKWebView                        Android WebView
      + WKNavigationDelegate           + WebViewClient
      + WKWebsiteDataStore             + CookieManager
      + Associated Domains             + Digital Asset Links
      + ASAuthorization (fallback)     + Credential Manager
          |                                 |
          +----------------+----------------+
                           |
                 HTTPS (TLS 1.2+/1.3)
                           |
                    Keycloak Server
                 (dedicated mobile realm
                  config + mobile theme)
                           |
            +--------------+--------------+
            |                             |
     Local credential store        Brokered web IdPs
     + passkeys + MFA              (allowlisted, §12.4)
```

Flow ownership:

- **React Native layer**: presentation orchestration, success/cancel/error callbacks, no security logic.
- **Native module (per platform)**: PKCE generation, WebView hardening, navigation filtering, redirect interception, code capture, token exchange, secure storage, attestation, telemetry.
- **Keycloak**: everything about *authentication itself*.

---

## 5. Security Threat Model

Baseline references: OWASP MASVS (v2), OWASP MASTG WebView guidance, OAuth 2.0 Security BCP, FAPI 2.0 (informative).

| # | Threat | Vector | Primary mitigations |
|---|---|---|---|
| T1 | Credential interception by host app | Malicious/compromised app reads WebView content | First-party boundary (§3.2); zero JS injection and no DOM access (§13); attestation invalidates repackaged apps (§16) |
| T2 | WebView compromise / renderer exploit | Malicious page content exploits WebView | Strict origin allowlist — only auth + broker domains ever load (§7.3); OS/WebView min-version floor (§25); no file/content URL access (§8, §9) |
| T3 | JavaScript injection | Any party injecting JS into auth pages | Forbidden by design; no `evaluateJavaScript` on auth origins; CI test asserts absence (§24) |
| T4 | Malicious redirect / open redirect | Auth flow navigated off-domain | Navigation delegate deny-by-default (§7.3); Keycloak strict redirect URI validation; broker allowlist (§12.4) |
| T5 | Authorization code theft | Code intercepted between Keycloak and native | Code captured only in native navigation delegate before any network dispatch (§6); PKCE S256 makes stolen code useless without verifier; verifier never leaves native memory |
| T6 | Session/cookie theft at rest | Extraction of persistent SSO cookie | Sandbox + FBE; `allowBackup=false`; no cloud backup of datastore; cookies `HttpOnly`+`Secure`+`SameSite` (§11.4); jailbreak/root posture (§17.3) |
| T7 | Session theft in transit | MITM | TLS 1.3 preferred, pinning policy (§15); no cleartext; ATS / networkSecurityConfig enforced |
| T8 | Fake login screen (phishing app) | Repackaged or impostor app mimics SEA | Attestation gates token issuance (§16); passkeys are origin-bound and unphishable (§10) |
| T9 | Deep-link / redirect-URI hijacking | Another app claims the redirect | HTTPS redirect URI intercepted in-WebView by navigation delegate — never dispatched as an OS intent (§6.2); no custom-scheme capture |
| T10 | Device compromise | Rooted/jailbroken device, overlay attacks, screen capture | Root/JB detection policy (§17.3); FLAG_SECURE + iOS capture posture (§17.1); `filterTouchesWhenObscured` (§17.2) |
| T11 | Passkey phishing | Fake origin requesting credential | WebAuthn origin binding + associated-domain / asset-links verification (§10); this is *stronger* in SEA than in a generic browser |
| T12 | Token theft at rest | Extraction of access/refresh tokens | Keychain (`WhenUnlockedThisDeviceOnly`) / Keystore-encrypted storage; no tokens in JS-reachable storage (§6.4) |
| T13 | Brokered-IdP abuse | Hostile or non-compliant third-party IdP | Per-IdP policy (§12.4); broker domains allowlisted individually; external-tab escape for non-compliant IdPs |
| T14 | Downgrade via kill switch abuse | Attacker forces fallback mode | Kill-switch config is signed remote config over pinned TLS; fallback mode is itself standards-compliant (§21) |

Residual risks accepted (record in the bank-facing risk register): fully compromised OS kernel; user coercion; zero-day in platform WebView (bounded by T2 mitigations and §21).

---

## 6. Authorization Code Handoff (Critical Path)

This is the security perimeter of the entire design. Everything in this section is normative.

### 6.1 PKCE and request construction (native only)

1. Native module generates `code_verifier` (43–128 chars, CSPRNG) and `code_challenge` (S256). The verifier is held in native process memory only — never bridged to JS, never written to disk, zeroed after exchange.
2. Native module generates `state` and `nonce` (CSPRNG, ≥128 bits each) and retains them for validation.
3. The authorization URL is constructed natively:

```
https://auth.bank.com/realms/{realm}/protocol/openid-connect/auth
  ?client_id=bankerise-mobile
  &response_type=code
  &redirect_uri=https://auth.bank.com/mobile/callback
  &scope=openid profile
  &code_challenge={S256(verifier)}
  &code_challenge_method=S256
  &state={state}
  &nonce={nonce}
  &ui_locales={ar|fr|en}
  [&prompt=login]            // forced fresh login contexts only
  [&kc_idp_hint={idp}]       // direct-to-broker entry points
  [&acr_values={level}]      // step-up contexts
```

### 6.2 Redirect URI strategy

- The redirect URI is an **HTTPS URL on the auth domain itself**: `https://auth.bank.com/mobile/callback`. It is registered in Keycloak with exact-match validation (no wildcards).
- The native navigation delegate (`WKNavigationDelegate.decidePolicyFor` / `WebViewClient.shouldOverrideUrlLoading`) matches this URL **before the request is dispatched**, cancels the navigation, and extracts `code` and `state` from the query.
- Because interception happens inside the app's own WebView pipeline, no OS-level intent/universal-link dispatch occurs → T9 is eliminated by construction. No custom scheme exists to hijack.
- The callback path serves a static "You can close this window" page server-side as defense-in-depth, but it must never be reached in practice.

### 6.3 Validation and exchange

1. Native validates returned `state` (constant-time compare). Mismatch → hard failure `AUTH_FAILED(state_mismatch)`, session discarded.
2. Native performs the token exchange **from the native HTTP client** (never the WebView):

```
POST https://auth.bank.com/realms/{realm}/protocol/openid-connect/token
  grant_type=authorization_code
  code={code}
  redirect_uri=https://auth.bank.com/mobile/callback
  client_id=bankerise-mobile
  code_verifier={verifier}
  + attestation evidence header (§16.3)
```

3. Client type: **public client + PKCE**, exchanged directly against Keycloak. (Deployment option B: exchange proxied through the Bankerise backend acting as confidential client, when a bank mandates it; the SEA contract is unchanged.)
4. ID token: signature, `iss`, `aud`, `exp`, and `nonce` validated natively before tokens are accepted.

### 6.4 Token custody

- Access/refresh tokens → iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) / Android EncryptedSharedPreferences or DataStore with Keystore-held key (StrongBox where available).
- Tokens are never exposed to the WebView, JS bridge, cookies, localStorage, or logs.
- Refresh-token rotation enabled realm-side; revocation on logout (§11.3).

---

## 7. React Native Component Design

### 7.1 Public API

```tsx
<SecureAuthenticationView
    realmUrl="https://auth.bank.com/realms/retail"
    clientId="bankerise-mobile"
    presentation="fullscreen"            // fullscreen | sheet
    locale="ar"                          // ar | fr | en → ui_locales
    idpHint={undefined}                  // optional kc_idp_hint
    prompt={undefined}                   // optional "login" for forced re-auth
    acrValues={undefined}                // optional step-up
    allowedDomains={[                    // exact-host allowlist
        "auth.bank.com",
        "idp.partner-example.com"        // brokered web IdPs, per §12.4
    ]}
    timeoutMs={120000}
    onAuthenticated={(result) => {}}     // { sessionEstablished: true } — never tokens
    onCancelled={() => {}}
    onError={(e: SEAError) => {}}
/>
```

Design rules:

- The JS layer receives an **opaque success signal**, never tokens. Token custody and refresh are the native module's job; RN consumes an authenticated session via the existing Bankerise session API.
- `allowedDomains` from JS is intersected with a **native-side compiled allowlist**; JS can narrow it, never widen it.
- All security-relevant configuration (redirect URI, client id per env, pinning sets) is compiled into the native module, not passed from JS.

### 7.2 Responsibilities

Lifecycle management (mount → pre-warm → present → dismiss), navigation filtering delegation to native, error taxonomy surfacing (`SEAError`: `network`, `timeout`, `cancelled`, `state_mismatch`, `server_error`, `attestation_failed`, `webauthn_unavailable`, `killed_switched`), and accessibility wiring (§19).

### 7.3 Navigation policy (normative)

- Deny by default. A navigation is permitted iff: scheme is `https` **and** host ∈ allowlist **and** it is a main-frame or same-origin subresource load.
- The redirect URI match (§6.2) preempts everything.
- `target=_blank` / new-window requests: opened in the same WebView if allowlisted, otherwise blocked. Never opened externally from within an auth flow, with the single exception of the broker external-tab escape (§12.4).
- `http:`, `file:`, `content:`, `intent:`, `javascript:`, custom schemes: blocked and reported as `AUTH_NAV_BLOCKED` telemetry.
- Downloads: blocked.

---

## 8. iOS Implementation

### 8.1 Structure

```
SEAViewController (UIViewController)
 |
 +-- Native header bar (back / title / close)   ← native, not web
 |
 +-- WKWebView
       |
       +-- Keycloak pages
```

### 8.2 WKWebView configuration

- `WKWebViewConfiguration` with:
  - `websiteDataStore = .default()` → persistent datastore, required for the persistent SSO cookie (§11). Note: WKWebView's default store is already **isolated from Safari**; no extra work needed for browser isolation.
  - `limitsNavigationsToAppBoundDomains = true` with the auth + broker domains declared under `WKAppBoundDomains` in Info.plist. This both enforces the allowlist at the platform level and is required context for service-worker/credential features.
  - `preferences.javaScriptCanOpenWindowsAutomatically = false`; `WKUIDelegate` handles window creation per §7.3.
  - `allowsInlineMediaPlayback` default; media capture permissions denied.
  - No `WKUserScript`s. No `evaluateJavaScript` calls targeting auth origins (bridge exception in §14).
- `WKNavigationDelegate`:
  - `decidePolicyFor navigationAction`: redirect-URI interception (§6.2) then allowlist enforcement (§7.3).
  - `didFailProvisionalNavigation` / `didFail`: mapped to `SEAError.network` with retry UI (§18.4).
  - TLS: `didReceive challenge` — default system validation plus pinning policy (§15). **Never** accept invalid certificates.
- Safe areas: WebView constrained to safe area; header bar handles the notch; keyboard avoidance via standard content-inset adjustment.

### 8.3 Credentials, AutoFill, passkeys

- **Associated Domains** entitlement: `webcredentials:auth.bank.com` (and `webcredentials` for any broker domain whose passkeys we would honor — normally none).
- Password AutoFill works in WKWebView for associated domains → iCloud Keychain suggestions appear on the Keycloak form with no code.
- Passkeys/WebAuthn: see §10. Face ID / Touch ID appears as part of the platform passkey ceremony — **SEA never invokes LocalAuthentication itself for login**; biometrics inside the auth flow always come from the platform authenticator to keep the ceremony origin-bound.
- Fallback ceremony path uses `ASWebAuthenticationSession` (§10.4).

### 8.4 Datastore custody

- The persistent `WKWebsiteDataStore` files live in the app sandbox with `NSFileProtectionCompleteUntilFirstUserAuthentication` (raise to `Complete` if background token refresh is not needed on locked devices — decision per deployment).
- Excluded from iCloud/iTunes backup (`isExcludedFromBackup` on the datastore directories where the OS honors it; document residual OS-managed paths in the security review).

---

## 9. Android Implementation

### 9.1 Structure

```
SEAActivity (or Fragment in RN host Activity)
 |
 +-- Native toolbar (back / title / close)
 |
 +-- WebView
       |
       +-- Keycloak pages
```

### 9.2 WebView configuration

```kotlin
webView.settings.apply {
    javaScriptEnabled = true            // required by Keycloak pages
    domStorageEnabled = true            // Keycloak login JS uses storage
    allowFileAccess = false
    allowContentAccess = false
    setSupportMultipleWindows(true)     // handled per §7.3
    setGeolocationEnabled(false)
    mixedContentMode = MIXED_CONTENT_NEVER_ALLOW
    safeBrowsingEnabled = true
}
WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)  // false in release
```

- `WebViewClient.shouldOverrideUrlLoading`: redirect-URI interception (§6.2) then allowlist (§7.3). `intent:` and custom schemes rejected.
- `onReceivedSslError`: **always** `handler.cancel()`. No user override, no debug bypass in release.
- `WebChromeClient`: window creation per §7.3; permission requests denied; JS dialogs rendered natively with origin shown.
- `networkSecurityConfig`: cleartext disabled globally; pin sets per §15.
- Cookies: `CookieManager` persists by default (required for §11); `setAcceptThirdPartyCookies(webView, false)` unless a specific broker requires it (per-IdP flag, §12.4).

### 9.3 Credential Manager, autofill, passkeys

- **Digital Asset Links**: `https://auth.bank.com/.well-known/assetlinks.json` includes the app's package + SHA-256 cert fingerprints with `delegate_permission/common.handle_all_urls` and `delegate_permission/common.get_login_creds`.
- Password autofill: the platform Autofill framework serves saved credentials into WebView forms for asset-linked domains.
- Passkeys/WebAuthn in WebView: enabled via `androidx.webkit` (`WebSettingsCompat.setWebAuthenticationSupport(settings, WEB_AUTHENTICATION_SUPPORT_FOR_APP)`), which routes WebAuthn calls to Credential Manager. Requires a current WebView provider and validated asset links. Exact minimum WebView/OS versions to be pinned during the platform spike and recorded in §25. See §10.
- Fallback ceremony path uses a Custom Tab (§10.4).

### 9.4 Data custody

- `android:allowBackup="false"`; `dataExtractionRules` exclude the WebView data directory and cookie databases from cloud backup and device transfer.
- File-based encryption assumed (min SDK floor guarantees it); no additional app-layer encryption of the cookie store in v1 (revisit if a deployment demands it).

---

## 10. Passkeys / WebAuthn (v1 Must-Have)

### 10.1 Ceremony model

Passkey registration and authentication are **Keycloak-driven WebAuthn ceremonies rendered in the SEA WebView**. The RP ID is the auth domain (`auth.bank.com`). SEA's job is to ensure the platform routes `navigator.credentials.create/get` calls to the OS platform authenticator with correct origin binding.

### 10.2 Platform enablement

| Platform | Mechanism | Preconditions |
|---|---|---|
| iOS | WKWebView WebAuthn for app-associated domains | `webcredentials:auth.bank.com` associated domain validated; app-bound domains configured (§8.2); minimum iOS version per §25 |
| Android | WebView → Credential Manager routing | `setWebAuthenticationSupport(FOR_APP)`; assetlinks.json validated; WebView provider ≥ floor version (§25) |

> **Engineering note (verify during spike):** WebAuthn-in-WebView support has changed across OS releases on both platforms and is the least stable dependency in this spec. The spike must produce the exact (OS, WebView, WKWebView) support matrix, feed §25, and validate both registration and authentication ceremonies plus conditional UI (autofill-style passkey suggestions), which may not be available in WebViews even where modal ceremonies are.

### 10.3 Keycloak configuration

- WebAuthn Register (passwordless) required action + WebAuthn Passwordless authenticator in the browser flow.
- RP ID fixed to the auth domain; attestation conveyance `none` (or `indirect` if the bank requires authenticator attestation — decide per deployment); user verification `required`.
- Passkey-first login flow with password as fallback, per bank policy.

### 10.4 Fallback ceremony path (normative)

If the WebView environment cannot perform WebAuthn (capability probe at SEA startup + runtime failure detection):

1. SEA detects the condition (`webauthn_unavailable`) — either pre-flight (OS/WebView version below floor) or live (ceremony JS error surfaced via Keycloak's error redirect).
2. The **entire login flow for that attempt** is handed to the system path: `ASWebAuthenticationSession` (iOS) / Custom Tab (Android) with the same authorization request parameters. This path is RFC-8252-clean by definition.
3. On completion, the same §6 handoff applies (the system path uses the same HTTPS redirect URI; on the fallback path it is captured via the session's callback mechanism).
4. Telemetry records the fallback (`AUTH_WEBAUTHN_FALLBACK`) so rollout dashboards show the embedded-vs-fallback ratio per OS version.

This is the same machinery as the kill switch (§21) applied per-attempt.

### 10.5 Why passkeys strengthen this design

WebAuthn credentials are origin-bound and verified against the associated-domain/asset-links chain, which cryptographically ties the ceremony to both the bank's domain **and** the genuine app package. A repackaged app fails asset-link validation and cannot exercise the user's passkey — directly mitigating T8/T11 and reinforcing the §3 argument.

---

## 11. Cookie and Session Management

### 11.1 Model: persistent app-scoped Keycloak SSO cookie

Selected model (per product decision): the Keycloak SSO session cookie (`KEYCLOAK_IDENTITY` et al.) persists in the WebView datastore across app restarts. Properties:

- Next login attempt: SEA opens the authorization URL → Keycloak sees a valid SSO cookie → immediately redirects with a fresh authorization code → §6 handoff → new tokens. **The user sees at most a flash of the loading state**; no credentials, near-silent re-auth.
- The SSO session is **app-scoped** (WKWebView default store is Safari-isolated; Android WebView cookies are app-private). No cross-app or system-browser SSO exists or is desired.
- Silent refresh: the same mechanism can be exercised in the background with `prompt=none` to re-establish sessions without UI; `login_required` error → surface interactive login.

### 11.2 Session timeline

```
First login
  WebView → Keycloak login (passkey/password + MFA)
    → SSO cookie written to persistent datastore
    → code → native exchange → tokens in Keychain/Keystore

App restart (within SSO idle/max window)
  WebView → authorize URL → cookie recognized → code → tokens
    (silent; optionally biometric-gated by the app shell before triggering)

SSO expiry / cookie cleared
  → full interactive login
```

Realm settings (dedicated mobile realm/client scope): SSO Session Idle and SSO Session Max define the re-auth cadence; set per bank policy (reference values: idle 30 days, max 90 days for retail; far stricter for corporate). Refresh token lifetimes ≤ SSO lifetimes; rotation on.

### 11.3 Logout (complete definition)

"Logout" in SEA means all of, atomically:

1. RP-initiated logout: native call to `.../protocol/openid-connect/logout` with `id_token_hint` → kills the Keycloak server-side session.
2. Refresh token revocation (defense in depth if (1) partially fails).
3. WebView datastore purge: `WKWebsiteDataStore.removeData(ofTypes: allWebsiteDataTypes)` / `CookieManager.removeAllCookies` + `WebStorage.deleteAllData`.
4. Keychain/Keystore token deletion.
5. `AUTH_LOGOUT_COMPLETED` event.

Back-channel logout: the mobile client registers a back-channel logout URI on the Bankerise backend; on admin-initiated session termination, the backend flags the session so the next API call returns 401 → app clears local state (steps 3–4) and shows login. The mobile device itself is not directly reachable — this indirection is the required pattern and must be stated to auditors.

### 11.4 Cookie hardening

Keycloak issues its session cookies `HttpOnly; Secure; SameSite` — verified in the deployment checklist (§26). At-rest protection per §8.4 / §9.4. Device-sharing scenarios: the app shell requires its normal unlock (device credential / biometric) before SEA silent re-auth is triggered; a "switch user" action performs full logout (§11.3) first.

---

## 12. Keycloak Integration

### 12.1 Flow

Authorization Code + PKCE only. Client `bankerise-mobile`: public, PKCE S256 enforced (`pkce.code.challenge.method=S256`), exact redirect URIs, no implicit/hybrid, no direct access grants, consent off (first-party).

### 12.2 Mobile realm configuration

- Dedicated client scope/flows for mobile; session lifetimes per §11.2.
- Brute-force protection on; WAF/rate limiting in front of the auth endpoints (embedded WebViews bypass some browser-level bot signals — compensate server-side; see also §16).
- Required actions supported as-is (update password, configure OTP, register passkey, verify email): they render in the WebView like any other Keycloak page. **No mobile release is needed for auth-flow changes** — this is a headline maintenance benefit; state it in bank-facing docs.

### 12.3 Custom authentication flows

Bank-specific flows (step-up via `acr_values`, transaction signing entry points, device-registration steps) are Keycloak authenticator SPI work, out of SEA scope but fully compatible: SEA passes `acr_values` through (§7.1) and renders whatever the flow serves.

### 12.4 Brokered third-party web-based IdPs

Scope per product decision: **web-based IdPs only** (no app2app in v1).

- Each broker IdP gets a policy entry in remote config:

```json
{ "alias": "partner-idp",
  "mode": "EMBEDDED",              // EMBEDDED | EXTERNAL_TAB
  "domains": ["idp.partner-example.com"],
  "thirdPartyCookies": false }
```

- `EMBEDDED`: broker domains are added to the navigation allowlist; the IdP renders inside SEA; Keycloak broker callback returns the flow to the auth domain and §6 proceeds normally.
- `EXTERNAL_TAB`: for IdPs that block embedded user-agents (Google's `disallowed_useragent` being the canonical case) or violate policy: when the navigation delegate sees a redirect to that IdP's authorize endpoint, SEA opens it in ASWebAuthenticationSession/Custom Tab, the broker's redirect back to `auth.bank.com` is captured by the session, and control returns to the embedded flow. This is the *only* sanctioned external navigation inside an auth attempt (§7.3).
- Detection: an unexpected 403/`disallowed_useragent`-pattern response from an EMBEDDED IdP raises `AUTH_BROKER_BLOCKED` telemetry and can be remotely flipped to `EXTERNAL_TAB` without a release.

### 12.5 No duplicated logic

Restated as a normative rule: the mobile layer contains **zero** knowledge of credential formats, MFA types, flow ordering, or password policy. If a change requires the app to "know" something new about authentication, the design is being violated.

---

## 13. Native/Web Boundary Security

Allowed native → web interactions:

```
Native
 |-- load authorization URL (§6.1)
 |-- cancel/deny navigations (§7.3)
 |-- capture redirect URI (§6.2)
 |-- purge datastore (§11.3)
 |-- close / dismiss the surface
```

Forbidden (normative, tested in CI per §24):

```
Native
 |-- read or observe page content, DOM, or fields
 |-- inject JavaScript or user scripts into auth origins
 |-- modify, restyle, or overlay authentication pages
 |-- extract cookies programmatically for use outside the WebView
 |-- proxy or MITM WebView traffic in-app
```

Rationale: any capability on the forbidden list, even if used benignly, is indistinguishable from credential-harvesting in a code audit and voids the §3 argument.

---

## 14. JavaScript Bridge Design

Default: **no bridge**. The redirect-URI interception (§6.2) makes a completion bridge unnecessary, and native chrome makes a close bridge unnecessary.

If a deployment demands page-initiated close (e.g., a Keycloak theme "Cancel" button), the maximal permitted bridge is:

```javascript
window.BankAuth = {
  close():      void   // request dismissal; native decides
  completed():  void   // advisory only; §6 interception remains the
                       // sole source of truth for success
}
```

- Registered only for the exact auth origin; receives no arguments; returns nothing; carries no tokens, credentials, or DOM access.
- iOS: `WKScriptMessageHandler` names `close`/`completed` only. Android: single `@JavascriptInterface` object with the two no-arg methods, added only when the top document origin is the auth domain.

---

## 15. Certificate and Network Security

- TLS 1.2 minimum, 1.3 preferred; ATS fully enforced (no exceptions) / `cleartextTrafficPermitted=false`.
- Certificate validation: full system chain validation always; `onReceivedSslError → cancel` with no override path (§9.2).
- **Pinning decision**: pin **SPKI hashes of the issuing CA(s)** for the auth domain (not leaf pins), with a backup pin set, delivered via platform mechanisms (`networkSecurityConfig` pin-set with expiry / native TrustKit-style evaluation on iOS) — applied to both the WebView (via the native TLS challenge hooks) and the native token-exchange client.
  - Rationale: leaf pinning has caused production outages in comparable deployments; CA-level SPKI pinning blocks rogue-CA MITM while surviving routine rotation.
  - Rotation strategy: pins carry expiry; new pins ship ≥1 release before certificate rotation; the kill switch (§21) is the break-glass path if a pin emergency ever bricks auth.
- No proxying of WebView traffic through app-level interceptors (§13).

---

## 16. Device Integrity and App Attestation

This section is the load-bearing compensating control for §3.

### 16.1 Mechanisms

- Android: **Play Integrity API** — standard verdict requested at SEA session start; verdict token attached to the token exchange.
- iOS: **App Attest** — key generated at install, assertion generated over the token-exchange payload hash.

### 16.2 Enforcement point

The Bankerise backend (or a Keycloak SPI, deployment-dependent) validates attestation evidence **at token exchange time** (§6.3). Policy per deployment tier:

| Verdict | Retail default | High-security deployments |
|---|---|---|
| Pass | Issue tokens | Issue tokens |
| Soft fail (e.g., basic integrity only) | Issue + flag risk engine | Step-up MFA |
| Hard fail (repackaged/emulator/hooked) | Deny + `attestation_failed` | Deny |

### 16.3 Effect

A repackaged app or a phishing look-alike can render a pixel-perfect fake login, but cannot complete a token exchange → T1/T8 collapse from "credential compromise" to "credential disclosure without account access," which existing Keycloak controls (password reset on risk signal, passkey migration) then bound. Combined with passkey origin binding (§10.5), the fake-app attack class is structurally closed.

---

## 17. Screen and Process Security

### 17.1 Capture protection

- Android: `FLAG_SECURE` on the SEA Activity/window → blocks screenshots, screen recording, and non-secure display mirroring; also blanks the recents/task-switcher thumbnail.
- iOS: task-switcher snapshot replaced with a branded cover view on `willResignActive`; `UIScreen.captured` monitored — active screen recording during SEA raises `AUTH_CAPTURE_DETECTED` and (policy per deployment) overlays a warning or blocks input. Screenshots cannot be blocked on iOS; `userDidTakeScreenshotNotification` is logged.

### 17.2 Overlay/tapjacking

- Android: `filterTouchesWhenObscured=true` on the WebView container; on supported OS versions, hidden-overlay touch policies enabled.

### 17.3 Root / jailbreak posture

- Detection via the existing Bankerise integrity module (native checks + Play Integrity/App Attest corroboration per §16).
- Policy is deployment-configurable: `BLOCK` (default for high-security banks) | `WARN_AND_FLAG` (risk-engine signal) — never silent-allow.

---

## 18. UX Specification

### 18.1 Surface

```
+--------------------------------+
|  ←                     Close   |   ← native header (not web)
+--------------------------------+
|                                |
|                                |
|      Keycloak mobile theme     |
|      (login / passkey / MFA)   |
|                                |
|                                |
+--------------------------------+
```

Rules (Binance-style):

- No address bar, no progress URL, no share/refresh, no browser affordances of any kind.
- Native header only: back (web history within the flow, else cancel) and close (cancel). Header title from app localization, not page `<title>`.
- No external navigation ever visible to the user (§7.3), except the §12.4 external-tab case which presents as a system sheet and returns automatically.
- Presentation: full-screen push or sheet per `presentation` prop; native transition animations; the WebView is pre-warmed so first paint is immediate (§22).

### 18.2 Keycloak mobile theme (required deliverable)

A dedicated `bankerise-mobile` Keycloak theme: mobile viewport, app brand tokens, light/dark following the app (`prefers-color-scheme` + theme param), RTL-correct Arabic layout, French/English variants via `ui_locales`, minimal chrome (no Keycloak header/footer), input types tuned for mobile keyboards, and passkey-first CTA layout. The theme is half of "feels native" — it ships with SEA v1, not later.

### 18.3 Loading states

Skeleton/branded spinner during initial load and during silent SSO re-auth (§11.1); the silent path should feel like an app splash, not a browser load.

### 18.4 Failure states

Native (not web) error surfaces for: offline, DNS/TLS failure, timeout (`timeoutMs`), server 5xx, `attestation_failed`, and kill-switch fallback engagement — each with retry or fallback actions and localized copy (ar/fr/en).

---

## 19. Accessibility

- VoiceOver/TalkBack: native header elements labeled; WebView content accessibility is inherited from the Keycloak theme — the theme must pass WCAG 2.1 AA (semantic form labels, focus order, error announcements).
- Keyboard/switch navigation: focus moves correctly between native header and web content.
- Dynamic type / font scaling: theme uses relative units; layout verified at 200% font scale in ar/fr/en.
- Reduced motion respected in native transitions.

---

## 20. Observability

### 20.1 Event taxonomy

```
AUTH_WEBVIEW_OPENED          { mode: embedded|fallback, prewarmed, locale }
AUTH_PAGE_LOADED             { page_class: login|otp|webauthn|reset|broker, ms }
AUTH_SILENT_SSO_ATTEMPTED    { }
AUTH_SILENT_SSO_RESULT       { outcome: success|login_required }
AUTH_WEBAUTHN_STARTED        { ceremony: get|create }
AUTH_WEBAUTHN_FALLBACK       { reason: preflight|runtime }
AUTH_BROKER_STARTED          { alias, mode }
AUTH_BROKER_BLOCKED          { alias }
AUTH_NAV_BLOCKED             { scheme, host_hash }
AUTH_COMPLETED               { total_ms, method_class }
AUTH_CANCELLED               { stage }
AUTH_FAILED                  { code: network|timeout|state_mismatch|server|attestation_failed }
AUTH_TIMEOUT                 { stage }
AUTH_CAPTURE_DETECTED        { kind: recording|screenshot }
AUTH_LOGOUT_COMPLETED        { }
AUTH_KILLSWITCH_ENGAGED      { source: remote|local_failure }
```

### 20.2 Data rules

Never logged, in events or crash reports: usernames, passwords, tokens, codes, cookies, full URLs with query strings (log path class only), broker user identifiers. Hostnames hashed where needed for cardinality. Funnel dashboards per OS version are the early-warning system for platform breakage (feeds §21).

---

## 21. Kill Switch / Remote Fallback

- Remote config key: `auth.mode = EMBEDDED | SYSTEM_BROWSER`, scoped by platform, OS version range, and app version, delivered over pinned TLS with signed config.
- `SYSTEM_BROWSER` mode routes the entire flow through ASWebAuthenticationSession / Custom Tabs with identical OAuth parameters — the standards-compliant path, always kept working and tested (§24).
- Automatic local trigger: N consecutive `AUTH_FAILED(network|server)` on the embedded path within a session → per-device temporary fallback + telemetry.
- Purpose: OS updates break WebView auth in the wild with some regularity; a config flip must resolve it in minutes across every bank deployment, without an app release.

---

## 22. Performance

- **Pre-warming**: instantiate the WebView (and process pool on iOS) at app start or on approach to the login surface; target first meaningful paint of the login page < 500 ms warm, < 1.5 s cold on reference devices.
- Silent SSO path (§11.1) budget: < 1.5 s end-to-end to tokens on a warm start, presented as splash continuity.
- Keycloak theme: minimal payload (< 200 KB critical path), HTTP/2, aggressive caching of theme assets with cache-busting on theme release.
- Metrics from §20 (`AUTH_PAGE_LOADED.ms`, `AUTH_COMPLETED.total_ms`) tracked per release with regression alerts.

---

## 23. Testing Strategy

### 23.1 Functional

Login (password, passkey, passkey-fallback path), silent SSO after restart, SSO expiry → interactive, logout completeness (all five steps of §11.3 verified), password reset, each MFA type in the realm, required actions, broker EMBEDDED and EXTERNAL_TAB modes, locale/RTL rendering, kill-switch mode end-to-end.

### 23.2 Security (mapped to MASVS)

- WebView hardening asserts: file/content access off, mixed content blocked, SSL error handling cancels, debug off in release.
- Static CI checks: no `evaluateJavaScript`/user scripts targeting auth origins; no `@JavascriptInterface` beyond §14; forbidden-list (§13) linting.
- Navigation fuzzing: malicious redirect corpus (open-redirect attempts, `javascript:`/`intent:`/custom schemes, look-alike domains, userinfo-URL tricks) — all must be blocked and telemetered.
- Handoff tests: state mismatch, code replay (second exchange must fail), PKCE downgrade attempt (plain challenge rejected), expired code.
- TLS: pin validation, invalid/self-signed/rotated-cert behavior, downgrade attempts.
- Attestation: repackaged build and emulator must fail exchange per §16.2 policy.
- Capture/overlay: FLAG_SECURE verified, tapjacking test with overlay app.
- Pen test scope note for bank security teams: SEA + Keycloak mobile realm + token exchange path, with §3 as the framing document.

### 23.3 Compatibility

Device-lab matrix over §25: WebAuthn ceremonies on each (OS, WebView) floor combination; annual re-validation at OS beta season (WebView auth is the component most likely to break in September).

---

## 24. CI/CD Guardrails

- The §13 forbidden list and §14 bridge maximum are enforced by lint rules failing the build.
- Release gate: functional suite (§23.1) green on reference devices for both `EMBEDDED` and `SYSTEM_BROWSER` modes — the fallback path must never rot.
- Config-schema validation for §12.4 and §21 remote config.

---

## 25. Compatibility Matrix (to be finalized in platform spike)

| Capability | iOS floor | Android floor | Below floor behavior |
|---|---|---|---|
| Embedded WebView login (no passkeys) | TBD (spike) | TBD (spike) | n/a — baseline |
| Passkeys in embedded WebView | TBD — associated-domain WebAuthn support version | TBD — WebView provider version with Credential Manager routing | §10.4 fallback ceremony |
| Conditional passkey UI (autofill suggestions) | TBD | TBD | Modal ceremony only |
| Play Integrity / App Attest | App Attest floor | Play services floor | §16.2 soft-fail policy |

> The spike deliverable is this table with exact versions plus the measured embedded-passkey success rate per OS version from a device-lab run. §21 thresholds are then set from real data.

---

## 26. Deployment Checklist

### iOS

- [ ] Associated Domains entitlement: `webcredentials:auth.bank.com` (per environment)
- [ ] `WKAppBoundDomains` in Info.plist: auth + approved broker domains
- [ ] App Attest capability + backend validation configured
- [ ] ATS: no exceptions in release
- [ ] Backup exclusion of datastore paths verified

### Android

- [ ] `assetlinks.json` deployed and validated (package + all release signing certs, incl. Play App Signing key)
- [ ] `networkSecurityConfig`: cleartext off, pin sets with expiry
- [ ] `allowBackup=false` + `dataExtractionRules` verified
- [ ] Play Integrity enabled + backend validation configured
- [ ] Minimum WebView provider floor enforced (in-app check → §21 fallback below floor)

### Keycloak / server

- [ ] Dedicated mobile client: public, PKCE S256 enforced, exact redirect URIs, DAG off
- [ ] Session lifetimes per §11.2 policy; refresh rotation on
- [ ] WebAuthn policy configured per §10.3; RP ID correct per environment
- [ ] `bankerise-mobile` theme deployed (ar/fr/en, RTL, dark mode)
- [ ] Cookies verified `HttpOnly; Secure; SameSite`
- [ ] `/mobile/callback` static completion page served
- [ ] Brute-force protection + WAF rules on auth endpoints
- [ ] Broker IdP policy config (§12.4) populated per environment
- [ ] Remote config: `auth.mode` wired and tested (§21)

---

## 27. Regulatory and Audit Notes

- §3 is the canonical answer to RFC 8252 findings; attach it to any bank security questionnaire.
- MASVS mapping: this spec addresses MASVS-AUTH, MASVS-NETWORK, MASVS-PLATFORM (WebView), MASVS-STORAGE (tokens/cookies), MASVS-RESILIENCE (§16, §17). A full control-by-control traceability sheet is produced per deployment.
- Where PSD2/SCA or GCC central-bank e-banking guidelines apply: SCA is enforced by Keycloak flows (inherence via passkey user verification / biometric platform authenticator; possession via device-bound passkey + attestation); dynamic linking, where required, is a Keycloak custom-flow concern (§12.3), out of SEA scope but compatible.
- Data residency: SEA introduces no new data flows; all traffic terminates at the bank's Keycloak.

---

## 28. Future Extensions

- Biometric **step-up** authentication via `acr_values` + Keycloak step-up flows (transaction signing surfaces reusing SEA).
- **Device binding** of sessions: DPoP-bound tokens or mTLS at the token endpoint, keyed in Secure Enclave/StrongBox — natural hardening layer on §6.
- **App2app national eID** brokering (UAE Pass, PACI): extends §12.4 with a third mode (`APP2APP`) using verified app links back into the flow.
- **Continuous authentication** signals (behavioral, device posture) feeding the bank risk engine at token refresh.
- **Voice authentication integration**: Bankerise Voice Trust Engine (speaker verification + anti-spoofing) as a Keycloak authenticator for voice-channel step-up, sharing the §16 attestation substrate.
- **AI risk engine integration**: §20 event stream as a real-time feature source for adaptive authentication policies.

---

*End of specification.*
