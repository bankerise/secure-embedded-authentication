# Bankerise Secure Embedded Authentication (SEA)

## Technical Specification — v1.2

| | |
|---|---|
| **Status** | Draft for review |
| **Version** | 1.2 |
| **Date** | 2026-07-20 |
| **Audience** | Bankerise platform engineering, mobile teams, security review, bank-side auditors |
| **Applies to** | Bankerise mobile apps (React Native, iOS + Android) authenticating against Keycloak |

> **v1.1 changes:** added the delivery architecture — standalone platform-native core SDKs (`sea-core-ios`, `sea-core-android`) with a thin React Native bridge (§1.3.5, §4.2–§4.8, §7), lockstep artifact versioning and release pipeline (§24), and native demo apps as the device-lab harnesses (§23.3).
>
> **v1.2 changes:** aligned with the Bankerise BFF architecture — the API Gateway (Spring Cloud Gateway + Spring Security) is the confidential OAuth2 client owning state, PKCE, code exchange, and token custody. §6 rewritten as gateway-anchored flow (`/authorization/start` → JSON authorize URL → custom-scheme callback capture → native code submission). No OAuth tokens ever exist on the device. Theme-parameter gating policy added (§6.2); threat model, sessions/logout, and checklists updated accordingly.
>
> **v1.3 changes:** device integrity attestation and TLS/certificate pinning are host-app and API Gateway responsibilities, not SEA's — the Bankerise Mobile SDK already performs app attestation against the gateway independently of SEA. §15 and §16 are retained as scope pointers only; all other sections' references to attestation/pinning as SEA-implemented controls have been removed accordingly.

---

## 1. Executive Summary

### 1.1 Purpose

This specification defines the Secure Embedded Authentication (SEA) component: a hardened, embedded WebView surface through which Bankerise mobile applications render and secure the user-facing portion of the OAuth 2.0 Authorization Code flow (with PKCE) against the bank's Keycloak identity provider. The flow itself is orchestrated by the Bankerise API Gateway acting as confidential OAuth2 client (BFF pattern, §6); SEA's mandate is to present the authentication surface, capture the callback, and hand its parameters to the Bankerise mobile SDK.

### 1.2 Problem Statement

Bankerise currently performs mobile login through an in-app system browser (SFSafariViewController / Chrome Custom Tabs). This is standards-compliant but produces a visibly non-native experience: browser chrome, address bar, a perceptible context switch, and inconsistent theming. For a flagship banking app, the login screen is the front door; it must feel like part of the app.

### 1.3 Design Philosophy

1. **First-party trust boundary.** The bank owns the app, the Keycloak realm, and the IdP domain. The classical argument against embedded WebViews — that a third-party app could observe user credentials — does not apply in the same way. We nevertheless treat the WebView as a semi-trusted surface and apply compensating controls (§3); device integrity attestation is one such control, owned by the host app/gateway (§16).
2. **Keycloak stays authoritative.** All authentication logic (credential validation, MFA orchestration, passkey ceremonies, password reset, brokering) lives in Keycloak. The mobile layer renders, isolates, and observes — it never re-implements authentication.
3. **The native/web seam is the security perimeter.** The single most sensitive interface in this design is the capture of the authorization callback in the WebView and its delivery to the Bankerise SDK (§6). It is specified exhaustively and everything else is forbidden by default (§13).
4. **Escape hatches are mandatory.** Embedded WebView authentication depends on OS behavior that changes across releases. Every deployment ships with a remotely-controllable fallback to system-browser authentication (§21).
5. **Core-first, bridge-thin.** All authentication, security, and WebView logic lives in standalone platform-native core SDKs with no React Native dependency. The RN layer is a marshalling bridge containing zero logic (§4.2, §7). This keeps the audited surface pure Swift/Kotlin, lets the hard platform work (passkeys, entitlements, WebView behavior) iterate in Xcode/Android Studio directly, and makes the native SDKs independently deliverable to banks with fully native apps.
6. **Gateway-anchored OIDC (BFF).** The Bankerise API Gateway (Spring Cloud Gateway + Spring Security) is the confidential OAuth2 client. State, PKCE, code exchange, and token custody are server-side; no OAuth tokens ever exist on the device. The device holds only a gateway session. SEA neither generates nor validates protocol parameters (§6).

### 1.4 Why Embedded Authentication Instead of Browser Redirects

- Full control of chrome: no address bar, no browser UI, native header with close/back.
- Seamless theming: Keycloak mobile theme + native transitions produce a login that is indistinguishable from a native screen.
- Deterministic lifecycle: native code controls presentation, dismissal, timeout, and error states.
- Industry precedent: Binance, Revolut, and the majority of tier-1 banking apps use embedded WebView login with a bank-owned IdP.

The trade-offs of this decision, and why they are acceptable, are recorded formally in §3.

---

## 2. Goals and Non-Goals

### 2.1 Goals

- G1. Render and secure the user-facing portion of the Authorization Code + PKCE login orchestrated by the Bankerise API Gateway (BFF, §6), inside an embedded, hardened WebView, implemented as standalone native SDKs on iOS (WKWebView) and Android (WebView), surfaced to React Native as a single thin component.
- G2. **Passkeys (WebAuthn) as a first-class v1 authentication method**, executed inside the embedded WebView where platform support allows, with a specified fallback ceremony path (§10).
- G3. Persistent Keycloak SSO session across app restarts via a persistent, protected cookie store (§11), producing near-silent re-authentication.
- G4. Support for Keycloak-brokered **third-party web-based IdPs** rendered within the embedded flow, with a per-IdP embed/external policy (§12.4).
- G5. Full support for Keycloak-driven MFA, required actions, and password reset without mobile releases.
- G6. Binance-grade UX: native header, no browser affordances, first-frame-fast (§18, §22).
- G7. Auditable security posture mapped to OWASP MASVS and the OAuth 2.0 Security BCP, with explicit documentation of the RFC 8252 deviation (§3).
- G8. SEA ships as three lockstep-versioned artifacts — an iOS XCFramework, an Android AAR, and a React Native library wrapping both (§4.2) — with the native SDKs independently consumable by fully native banking apps and auditable in isolation from any RN tooling.

### 2.2 Non-Goals

- OAuth protocol mechanics on the device. State, PKCE, code exchange, and token custody belong to the Bankerise API Gateway acting as confidential client (§6). SEA neither constructs authorization requests nor interprets callback parameters beyond capturing them.
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
| Storing tokens anywhere on the device | No OAuth tokens exist on the device; custody is gateway-side (§6.5) |

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

1. **Reason (1) assumes an adversarial client.** SEA is a first-party component: the party that could theoretically capture credentials (the bank's app) is the same party that receives them legitimately (the bank's IdP). Moreover, under the BFF architecture (§6) the mobile client is not even an OAuth client: the confidential client with its secret, PKCE verifier, and all tokens lives server-side at the gateway — the device has strictly less to steal than in the RFC-recommended public-client browser flow. The residual risk is a *compromised* app binary; mitigating that residual risk (device integrity attestation, §16) is a host-app/gateway concern outside SEA's mandate.
2. **Reason (2) is a non-goal.** We do not want browser-shared SSO for a banking app; the app-scoped persistent session (§11) is deliberate.
3. **Reason (3) is mitigated structurally**, not cosmetically: the observability pipeline (§20) detects anomalous auth funnels, and — outside SEA — device integrity attestation at the gateway means a fake app presenting a fake login screen cannot complete session establishment (§16).
4. **Reason (4) is handled per-IdP** via the broker embed/external policy (§12.4) and the global kill switch (§21).

### 3.3 Alternatives considered

| Alternative | Verdict |
|---|---|
| ASWebAuthenticationSession / Custom Tabs (status quo) | Standards-ideal; rejected on UX grounds (browser chrome, context switch). Retained as the **fallback mode** (§21) and as the passkey fallback ceremony path (§10.4). |
| `prefersEphemeralWebBrowserSession` + heavy theming of system sheet | Still shows browser chrome; does not meet G6. |
| Native login UI + Direct Access Grants | Rejected outright (§2.2). |
| Fully native OIDC ceremony via AppAuth + custom Keycloak REST | Reimplements Keycloak flows in mobile; breaks G5; unmaintainable across MFA/passkey/required-action evolution. |

### 3.4 Compensating controls summary

Embedded WebView (this spec) + confidential-client BFF with server-side state/PKCE/token custody (§6) + navigation allowlisting (§7.3) + in-process callback capture (§6.3) + zero JS injection (§13) + screen security (§17) + remote kill switch (§21) + auth-funnel observability (§20). Outside SEA, the host app/gateway additionally apply device integrity attestation gating session establishment (§16) and a TLS pinning policy (§15).

---

## 4. High-Level Architecture

### 4.1 Runtime architecture

```
                     Bankerise Mobile App
                             |
             +---------------+----------------+
             |                                |
   Bankerise Mobile SDK               React Native Layer
   (native; gateway session      <SecureAuthenticationView/>
    custody, /authorization/start,        |
    code submission)              Secure Authentication Core
             |                     (sea-core, per platform)
             |                            |
             |                 WKWebView / Android WebView
             |                 + navigation delegate/client
             |                 + persistent datastore
             |                 + Associated Domains /
             |                   Digital Asset Links
             |                            |
             |                    HTTPS (TLS 1.2+/1.3)
             |                            |
             |                     Keycloak Server
             |                  (dedicated mobile realm,
             |                   mobile theme, passkeys,
             |                   MFA, brokered web IdPs)
             |                            ^
   HTTPS (native client,                  |
    pre-auth → authenticated              | token endpoint
    Spring Session cookie)                | (confidential exchange)
             |                            |
             +-----> Bankerise API Gateway
                     (Spring Cloud Gateway + Spring Security:
                      confidential OAuth2 client — state, PKCE,
                      code exchange, token custody, Spring Session)
```

The WebView communicates **only with Keycloak** (and allowlisted broker IdPs). The gateway is reached exclusively by the native HTTP client. The two cookie domains never mix (§6.5).

Flow ownership:

- **Bankerise Mobile SDK** (native, outside SEA): calls `/authorization/start`, receives the authorize URL, submits captured callback parameters to the gateway, owns the gateway session end-to-end.
- **SEA core (per platform)**: hardened WebView surface, authorize-URL integrity validation, navigation filtering, callback capture, datastore lifecycle, screen security, telemetry.
- **Bankerise API Gateway**: confidential OAuth2 client — authorization request construction, state + PKCE custody, code exchange, token custody, session management.
- **React Native layer**: presentation orchestration, success/cancel/error callbacks, no security logic.
- **Keycloak**: everything about *authentication itself*.

### 4.2 Artifact architecture

SEA is developed core-first (§1.3.5) and delivered as three artifacts:

```
     sea-core-ios                  sea-core-android
  Swift Package                    Gradle library
  → signed XCFramework             → AAR
        \                              /
         \                            /
              sea-react-native
        thin Fabric bridge, zero logic,
        depends on exact core versions
        → npm package
```

| Artifact | Contains | Consumers |
|---|---|---|
| `sea-core-ios` / `sea-core-android` | Everything in §§5–17 within SEA's mandate: WebView surface, navigation policy, §6.2 URL validation, §6.3 callback capture, datastore/session lifecycle, screen security, telemetry emission. No RN dependency of any kind. Device integrity attestation and TLS pinning (§15, §16) are host-app/gateway concerns, not part of this artifact. | `sea-react-native`; fully native bank apps (direct SDK integration); future non-RN wrappers (§28) |
| `sea-react-native` | Prop/config marshalling in, event marshalling out. **No authentication, navigation, storage, crypto, or networking logic** — enforced by lint (§24). | Bankerise RN apps |

Consequences this buys, stated for the record: (a) the bank-facing security review and pen test scope (§23.2) is a pure Swift/Kotlin codebase with no Metro/JSI/node_modules in scope; (b) the platform-fragile work — passkeys, entitlements, WebView behavior — iterates in Xcode/Android Studio via native demo apps without an RN build in the loop; (c) the native SDKs are standalone deliverables for banks with existing native apps.

### 4.3 Core API contract

The two cores expose deliberately mirror-image APIs, documented as a versioned contract file in `docs/` that both platforms and the bridge conform to:

- `SEASession.start(config) → callbacks` — config carries the gateway-issued `authorizeUrl` (§6.1), the `callbackScheme`, presentation, timeout, and the JS-narrowable domain allowlist (§7.1 rules unchanged). Parameters that shape the authorization request itself (locale, `kc_idp_hint`, `prompt`, `acr_values`, theme params) are **not** SEA config — the Bankerise SDK passes them to `/authorization/start` (§6.1–§6.2).
- `SEAAuthView` — `UIViewController` / `Fragment` hosting the hardened WebView surface (§8.1, §9.1).
- Callbacks: `onCaptured(params)` delivering the callback parameters verbatim (§6.3), `cancelled`, and the `SEAError` taxonomy (§7.2). SEA never interprets `code`/`state` semantics — that is the gateway's job (§6.4).
- All event and error payloads are defined as **serializable structs in the cores**; the bridge translates struct → `WritableMap` and nothing else (§7.4).

Any change to authentication behavior that would require the contract to grow "knowledge" of credential formats or flow ordering violates §12.5, regardless of which layer it lands in.

### 4.4 Repository layout

Dedicated monorepo, independent of Bankerise:

```
sea/
  packages/
    sea-core-ios/          # Swift package
    sea-core-android/      # Gradle library module
    sea-react-native/      # bridge (codegen specs + glue)
  apps/
    demo-ios/              # native harness — primary device-lab app (§23.3)
    demo-android/          # native harness — primary device-lab app (§23.3)
    demo-rn/               # bridge validation only
  infra/                   # Keycloak compose + realm export + AASA/assetlinks
  docs/                    # this spec, API contract, §25 matrix results
```

### 4.5 Packaging and distribution

- **iOS**: Swift Package for native consumers. The RN podspec consumes the core by local path during development; releases vendor the CI-built, signed XCFramework. (This dual-mode setup is the main build-plumbing cost of the architecture; it is paid once.)
- **Android**: composite/`includeBuild` project dependency during development; releases publish the AAR to a Maven registry (GitHub Packages or bank-hosted Nexus for air-gapped deployments).
- **RN**: npm package pinning exact core versions (§4.6).

### 4.6 Versioning policy

Lockstep semantic versioning across all three artifacts: `sea-react-native@X.Y.Z` pins `sea-core-*@X.Y.Z` exactly, and all three are released together by a single pipeline (§24). Independent version drift between cores and bridge is prohibited in v1 — the flexibility buys nothing and costs a compatibility matrix.

### 4.7 Threading and callback contract

Normative, because WKWebView/WebView are main-thread-bound and RN calls in from its own threads: **all public core API is main-thread-only; all callbacks are delivered on the main thread.** The cores enforce this with debug assertions at every public entry point; the bridge is responsible for hopping to main before delegating.

### 4.8 Build phasing

Phases 1–2 (the §6 handoff perimeter and the §10/§25 passkey spike) are implemented entirely in the cores, driven by the native demo apps — RN is not in the critical path and need not be installed. The bridge is a separate workstream that starts once the core API contract (§4.3) stabilizes at the end of Phase 1, so auth is never debugged *through* the bridge.

---

## 5. Security Threat Model

Baseline references: OWASP MASVS (v2), OWASP MASTG WebView guidance, OAuth 2.0 Security BCP, FAPI 2.0 (informative).

| # | Threat | Vector | Primary mitigations |
|---|---|---|---|
| T1 | Credential interception by host app | Malicious/compromised app reads WebView content | First-party boundary (§3.2); zero JS injection and no DOM access (§13); outside SEA, host-app/gateway attestation invalidates repackaged apps (§16) |
| T2 | WebView compromise / renderer exploit | Malicious page content exploits WebView | Strict origin allowlist — only auth + broker domains ever load (§7.3); OS/WebView min-version floor (§25); no file/content URL access (§8, §9) |
| T3 | JavaScript injection | Any party injecting JS into auth pages | Forbidden by design; no `evaluateJavaScript` on auth origins; CI test asserts absence (§24) |
| T4 | Malicious redirect / open redirect | Auth flow navigated off-domain | Navigation delegate deny-by-default (§7.3); Keycloak strict redirect URI validation; broker allowlist (§12.4) |
| T5 | Authorization code theft | Code intercepted between Keycloak and gateway | Captured in-process before any dispatch (§6.3); a stolen code is unusable in isolation: exchange requires the gateway's client secret, the server-held PKCE verifier, and the pre-auth session binding held by the native client (§6.4) |
| T6 | Session/cookie theft at rest | Extraction of persistent SSO cookie | Sandbox + FBE; `allowBackup=false`; no cloud backup of datastore; cookies `HttpOnly`+`Secure`+`SameSite` (§11.4); jailbreak/root posture (§17.3) |
| T7 | Session theft in transit | MITM | TLS 1.3 preferred; no cleartext; ATS / networkSecurityConfig enforced; TLS pinning, where used, is a host-app/gateway policy (§15) |
| T8 | Fake login screen (phishing app) | Repackaged or impostor app mimics SEA | Passkeys are origin-bound and unphishable (§10); outside SEA, host-app/gateway attestation gates token issuance (§16) |
| T9 | Deep-link / callback hijacking | Another app registers the callback scheme | Embedded mode: the custom-scheme callback is intercepted and cancelled inside the navigation delegate — it never reaches OS dispatch (§6.3). Fallback mode: OS dispatch is possible, but T5's triple binding renders a hijacked code worthless (§10.4) |
| T10 | Device compromise | Rooted/jailbroken device, overlay attacks, screen capture | Root/JB detection policy (§17.3); FLAG_SECURE + iOS capture posture (§17.1); `filterTouchesWhenObscured` (§17.2) |
| T11 | Passkey phishing | Fake origin requesting credential | WebAuthn origin binding + associated-domain / asset-links verification (§10); this is *stronger* in SEA than in a generic browser |
| T12 | Token theft at rest | Extraction of access/refresh tokens | No OAuth tokens exist on the device — all token custody is gateway-side (§6.5). Native custody is limited to the Spring Session cookie: Keychain/Keystore-protected storage, never exposed to the WebView or JS |
| T13 | Brokered-IdP abuse | Hostile or non-compliant third-party IdP | Per-IdP policy (§12.4); broker domains allowlisted individually; external-tab escape for non-compliant IdPs |
| T14 | Downgrade via kill switch abuse | Attacker forces fallback mode | Kill-switch config is signed remote config over pinned TLS; fallback mode is itself standards-compliant (§21) |

Residual risks accepted (record in the bank-facing risk register): fully compromised OS kernel; user coercion; zero-day in platform WebView (bounded by T2 mitigations and §21).

---

## 6. Authorization Flow and Callback Capture (Critical Path)

This is the security perimeter of the entire design. The flow is gateway-anchored (BFF): the Bankerise API Gateway (Spring Cloud Gateway + Spring Security) is the confidential OAuth2 client; SEA renders the user-facing leg and captures the callback. Everything in this section is normative.

### 6.1 Flow topology

```
Bankerise SDK              SEA WebView          API Gateway              Keycloak
(native HTTP client)
   |
   | POST /authorization/start
   |   { locale, prompt?, acr_values?,
   |     kc_idp_hint?, theme params }
   |----------------------------------------->|
   |                                          | resolves which client_id this
   |                                          | authorization belongs to
   |                                          | (multi-client routing — out of
   |                                          |  SEA scope) and decides authMode
   |<-- 200 { redirect:                       |
   |      "/oauth2/authorization/{client_id}",|
   |      authMode: "EMBEDDED",   // default  |
   |      provider: "gw" } -------------------|
   |
   | GET {redirect}  (Spring Security filter)
   |----------------------------------------->|
   |                                          | builds OAuth2AuthorizationRequest:
   |                                          | state + PKCE verifier generated and
   |                                          | stored server-side, bound to the
   |                                          | pre-auth Spring Session
   |<-- 200 { redirectUrl:                    |
   |      "{KEYCLOAK_AUTHORIZATION_URL}",     |
   |      provider: "gw" } -------------------|
   |    + Set-Cookie: SESSION (pre-auth,      |
   |      into the NATIVE cookie jar)         |
   |
   | if authMode == EMBEDDED:
   |   SEASession.start(redirectUrl)
   | if authMode == SYSTEM_BROWSER:
   |   classic in-app browser flow (§21)
   |------------------>|
   |                   | validates URL (§6.2), loads it
   |                   |-------------------------------------------------->|
   |                   |            user authenticates                     |
   |                   |            (passkeys / MFA / brokers, §10, §12)   |
   |                   |<-- 302  {scheme}://callback?code=...&state=... ---|
   |                   | intercepted IN-PROCESS (§6.3),
   |                   | navigation cancelled, params extracted
   |<- onCaptured({code, state, ...}) --|
   |
   | GET/POST /login/oauth2/code/{registrationId}
   |   ?code=...&state=...   (+ attestation evidence, §16 — host-app/gateway concern)
   |   (pre-auth SESSION cookie attached automatically)
   |----------------------------------------->|
   |                                          | validates state against stored
   |                                          | request; exchanges code as
   |                                          | CONFIDENTIAL client with the
   |                                          | server-held verifier ------------>|
   |                                          | establishes authenticated
   |                                          | Spring Session; tokens stay
   |                                          | server-side
   |<-- authenticated session ----------------|
```

Division of labor: steps outside the WebView column are the Bankerise Mobile SDK's and the gateway's responsibility — specified here as the platform flow, out of SEA's implementation scope. SEA implements §6.2 and §6.3 only; mode selection happens before SEA is ever instantiated (§21). The two-hop start (`/authorization/start` → `redirect` → `redirectUrl`) exists because the gateway performs multi-client routing on a single instance; SEA only ever sees the final `redirectUrl`.

### 6.2 Authorize URL integrity and parameter gating

**URL integrity (SEA-enforced).** The start sequence returns the Keycloak authorize URL (`redirectUrl`, §6.1) in a JSON body rather than a 302. Because this URL arrives as data, SEA validates it before first load: scheme must be `https`; host must be in the **compiled** auth-domain allowlist (JS-supplied `allowedDomains` can narrow, never widen, §7.1); no userinfo component, no non-standard port, total length ≤ 2 KB. Any violation → `AUTH_FAILED(invalid_authorize_url)`, nothing is loaded.

**Parameter gating (gateway-enforced).** All parameters that shape the authorization request enter at `/authorization/start` and pass through the gateway's customized `OAuth2AuthorizationRequestResolver` in three tiers:

- **Tier 1 — protocol parameters, gateway-owned, non-overridable:** `client_id`, `redirect_uri`, `response_type`, `scope`, `code_challenge`, `code_challenge_method`, `state`, `nonce`. Nothing supplied by the caller can set or shadow these.
- **Tier 2 — known semantic parameters, typed and validated per-field:** `ui_locales`, `kc_idp_hint`, `prompt`, `acr_values`.
- **Tier 3 — theme decoration, free-form but gated:** integrator-supplied theme parameters (dark mode, platform, biometric enrollment state, etc.) under a mandatory namespace:

```
key pattern      ^theme_[a-z0-9_]{1,32}$        (namespace makes collision with
                                                 tier 1/2 structurally impossible)
reserved set     all OAuth/OIDC params, kc_*    (defense in depth atop the pattern)
value            ≤128 chars, printable subset, no URLs/schemes
count / size     ≤10 params; final URL ≤ 2 KB
encoding         resolver percent-encodes; never string concatenation
violations       parameter dropped + AUTH_PARAM_REJECTED telemetry (never silent)
```

Theme parameters are **public by definition** — they appear in Keycloak, proxy, and WAF access logs. Nothing more sensitive than coarse presentation/device-posture hints (e.g. `theme_biometric_enrolled`) may ride tier 3; this classification is part of the bank-facing data inventory (§27).

### 6.3 Callback capture (SEA-enforced)

- The redirect URI is a **custom scheme** (e.g. `bankerise-auth://callback`), registered with exact-match validation in Keycloak and compiled into SEA as `callbackScheme`.
- The navigation delegate (`WKNavigationDelegate.decidePolicyFor` / `WebViewClient.shouldOverrideUrlLoading`) matches the scheme, **cancels the navigation before any dispatch**, and extracts all query parameters. Because interception happens inside the app's own WebView pipeline, the scheme never reaches the OS — no intent resolution, no other app in the race (T9).
- **POST-redirect backstop (Android, normative):** `shouldOverrideUrlLoading` is not invoked for POST submissions, and redirect-after-POST behavior — exactly the shape of a Keycloak credential form POST → 302 → callback — has varied across WebView versions. The callback URL is therefore *also* checked in `onPageStarted` / `doUpdateVisitedHistory` as a backstop. iOS's `decidePolicyFor` reliably covers server redirects after POST; the same double-check is applied there at zero cost.
- Captured parameters (`code`, `state`, `session_state`, or `error` + `error_description` on failure) are delivered **verbatim** to the host via `onCaptured(params)`. SEA performs no semantic validation of them — state verification and code exchange are the gateway's job. Error-shaped callbacks are delivered through the same channel, not swallowed.

### 6.4 Code submission and session establishment (Bankerise SDK + gateway)

- The native client submits the captured parameters to the gateway's `/login/oauth2/code/{registrationId}` endpoint. The pre-auth `SESSION` cookie from `/authorization/start` rides automatically in the native cookie jar — this is the binding that makes the flow coherent.
- The gateway validates `state` against the stored `OAuth2AuthorizationRequest`, then exchanges the code at Keycloak's token endpoint as a **confidential client** with the server-held PKCE verifier, and upgrades the session to authenticated.
- Consequence, stated for the threat model: a stolen authorization code is unusable in isolation. Exchange requires (a) the gateway's client secret, (b) the PKCE verifier that never left the server, and (c) the pre-auth session cookie held only by the genuine native client. All three are out of reach of a scheme-hijacking or code-intercepting attacker.
- Attestation evidence (Play Integrity / App Attest, §16) is attached to `/authorization/start` and/or the code submission by the Bankerise Mobile SDK, independently of SEA; the gateway is the enforcement point (§16.2). This is entirely a host-app/gateway concern — SEA neither collects nor transmits attestation evidence.

### 6.5 Session and token custody

- **No OAuth tokens exist on the device.** Access, refresh, and ID tokens live at the gateway; token refresh against Keycloak is a server-side concern, invisible to mobile.
- Native custody is limited to the gateway **Spring Session cookie**, held in the native HTTP client's cookie jar backed by Keychain / Keystore-protected storage. It is never exposed to the WebView, the JS bridge, or logs.
- The WebView's cookie jar contains **only Keycloak cookies** (SSO persistence, §11). The WebView never communicates with the gateway, so the two cookie domains never mix — and §13's prohibition on programmatic cookie extraction holds absolutely, with no exceptions.

---

## 7. React Native Bridge (`sea-react-native`)

This section specifies the RN-facing surface. Per §4.2, this package is a marshalling bridge only: every prop maps to a core config field, every callback maps to a core event struct, and it contains no authentication, navigation, storage, crypto, or networking logic of its own.

### 7.1 Public API

```tsx
<SecureAuthenticationView
    authorizeUrl={startSeq.redirectUrl}        // gateway-issued (§6.1);
                                               // origin-validated by the core (§6.2)
    callbackScheme="bankerise-auth"            // compiled default; JS may not change
    presentation="sheet"                       // sheet (default, §18.1) | fullscreen
    appearance={{                              // colors & text only (§18.1)
        headerBackground, headerText, accent,
        title: undefined,                      // undefined → live page title
        closeIconTint, cornerRadius
    }}
    allowedDomains={[                          // narrowing only, §7.3
        "auth.bank.com",
        "idp.partner-example.com"              // brokered web IdPs, per §12.4
    ]}
    timeoutMs={120000}
    onCaptured={(params) => {}}                // verbatim callback params →
                                               // Bankerise SDK → gateway (§6.4)
    onCancelled={() => {}}
    onError={(e: SEAError) => {}}
/>
```

Design rules:

- Parameters that shape the authorization request (locale, `kc_idp_hint`, `prompt`, `acr_values`, theme params) are **not** SEA props — the Bankerise SDK passes them to `/authorization/start` (§6.1–§6.2). SEA receives a finished URL and validates it.
- `onCaptured` delivers parameters, not conclusions: whether authentication *succeeded* is decided by the Bankerise SDK after the gateway call (§6.4). SEA never sees tokens or sessions.
- `allowedDomains` from JS is intersected with a **native-side compiled allowlist**; JS can narrow it, never widen it.
- All security-relevant configuration (callback scheme, compiled domain allowlist per env) is compiled into the native core, not passed from JS. TLS pinning sets, if a deployment uses them, are a host-app/gateway networking-client concern (§15), not part of this compiled config.

### 7.2 Responsibilities

Lifecycle management (mount → pre-warm → present → dismiss), navigation filtering delegation to native, error taxonomy surfacing (`SEAError`: `network`, `timeout`, `cancelled`, `invalid_authorize_url`, `server_error`, `webauthn_unavailable`, `kill_switched`), and accessibility wiring (§19). Gateway-side failures (state mismatch, attestation rejection outside SEA's scope, exchange errors) surface through the Bankerise SDK's code-submission call, not through SEA.

### 7.3 Navigation policy (normative)

- Deny by default. A navigation is permitted iff: scheme is `https` **and** host ∈ allowlist **and** it is a main-frame or same-origin subresource load.
- The callback-scheme match (§6.3) preempts everything.
- `target=_blank` / new-window requests: opened in the same WebView if allowlisted, otherwise blocked. Never opened externally from within an auth flow, with the single exception of the broker external-tab escape (§12.4).
- `http:`, `file:`, `content:`, `intent:`, `javascript:`, and custom schemes other than the registered `callbackScheme`: blocked and reported as `AUTH_NAV_BLOCKED` telemetry.
- Downloads: blocked.

### 7.4 Bridge implementation notes

- New-architecture-first: the auth surface is a **Fabric native component**; lifecycle and imperative interactions go through component commands/events rather than a separate module where possible.
- Codegen specs live in this package; generated glue delegates immediately into `sea-core-*` with no intermediate logic.
- Event payload translation is mechanical: core-defined structs (§4.3) → `WritableMap`. The `SEAError` taxonomy crosses the bridge unchanged.
- Main-thread hop before every core call, per §4.7.
- Bridge purity is CI-enforced (§24): bridge sources may not import networking, crypto, storage, or WebView APIs.

> **Implementation status (v1 spike — iOS):** `sea-react-native` is scaffolded (`packages/sea-react-native`, Fabric new-architecture view, `create-react-native-library`-generated codegen glue) and consumes `sea-core-ios` in dev mode exactly as §4.5 describes: a thin `SEACore.podspec` was added (no logic change to the core — one `#if SWIFT_PACKAGE` seam in `SEAStrings.swift` so `Bundle.module` still resolves under CocoaPods, since that symbol is SwiftPM-only) and `apps/demo-rn`'s Podfile pins it by local `:path`. All bridge-side logic is a single Swift shim (`SEABridgePresenter.swift`) that builds a `SEAConfig` from primitive props and calls `SEASession.start` — the ObjC++ Fabric view (`SeaReactNativeView.mm`) only marshals props in and events out, matching §7.4.
>
> Validated end to end on the iOS 26.5 Simulator against the same local Keycloak realm/theme `demo-ios` uses: mounting `<SecureAuthenticationView authorizeUrl=.../>` presents the real embedded WebView as a sheet — confirming the props → native direction — and an off-allowlist `authorizeUrl` correctly fires `onError({code: 'invalid_authorize_url', message: 'host'})` back in JS — confirming the native → event direction and that `SEAError`'s taxonomy crosses the bridge unchanged. The interactive golden path (submitting the login form / passkey ceremony from JS) was not driven by touch automation in this pass — no accessibility-automation permission was available in the environment this was built in — but exercises the identical `SEASession`/`SEAAuthViewController` code path already validated via `demo-ios`, so the remaining bridge-specific risk (Fabric prop/event marshalling) is what was targeted and confirmed above. Android (`sea-core-android` / bridge glue) is not implemented — out of scope until a native Android core exists.
>
> **Correction (found after initial validation):** the first pass of `apps/demo-rn` did not carry `apps/demo-ios`'s `com.apple.developer.associated-domains` entitlement — the RN CLI scaffold has no XcodeGen-driven entitlements wiring, so nothing added one. Without it, Keycloak's client-side WebAuthn capability check fails and the login page silently falls back to password-only — the passkey-first CTA never rendered, no error surfaced. Fixed by adding `apps/demo-rn/ios/demo_rn/demo_rn.entitlements` (`webcredentials:auth.bank.local?mode=developer`, identical to `demo-ios`'s), wiring it via `CODE_SIGN_ENTITLEMENTS`, correcting `demo-rn`'s bundle identifier (was left at the RN CLI default `org.reactjs.native.example.demo_rn` instead of `com.bankerise.sea.demorn`, which its own URL-scheme config already assumed), and adding that bundle ID to `infra/nginx/apple-app-site-association`'s `apps` array alongside `demo-ios`'s. Re-verified after the fix: the "Sign in with Passkey" CTA now renders correctly.
>
> **UI parity (added after user feedback):** `apps/demo-rn` initially had one bare screen; it now has Config/Result/Telemetry tabs mirroring `apps/demo-ios`'s ConfigView/ResultsView/TelemetryConsoleView (hand-rolled tab switching, no navigation library — three tabs isn't worth the dependency). `apps/demo-ios`'s Fuzz view is intentionally not ported — it drives `SEACore`'s internal Swift-only fuzz harness directly, outside the bridge surface `sea-react-native` exposes. Telemetry (§20) and purge-web-data (§11.3) cross the bridge via a second, non-visual native module, `SeaTelemetryEmitter` (`packages/sea-react-native/ios/SeaTelemetryEmitter.swift`) — a classic `RCTEventEmitter`/`RCTBridgeModule`, since Fabric's codegen is view-only and this has no visual surface. Verified: `subscribeToTelemetry` correctly received `AUTH_WEBVIEW_OPENED` → `AUTH_PAGE_LOADED` → `AUTH_TIMEOUT` from a real `SEASession.start` run, with the JS-side Result screen showing the resulting `onError({code:'timeout'})` after auto-dismiss. Demo-rn settings are in-memory only, not persisted across launches like `demo-ios`'s `UserDefaults` (no AsyncStorage-equivalent dependency added).

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
  - `decidePolicyFor navigationAction`: callback capture (§6.3) then allowlist enforcement (§7.3).
  - `didFailProvisionalNavigation` / `didFail`: mapped to `SEAError.network` with retry UI (§18.4).
  - TLS: `didReceive challenge` — default system chain validation only. **Never** accept invalid certificates. TLS pinning, if a deployment requires it, is applied by the host app's own networking client (§15), outside SEACore.
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

- `WebViewClient.shouldOverrideUrlLoading`: callback-scheme capture first — the registered `callbackScheme` is intercepted and cancelled in-process (§6.3); all other `intent:`/custom schemes rejected; then allowlist (§7.3). The §6.3 POST-redirect backstop is implemented in `onPageStarted`/`doUpdateVisitedHistory`.
- `onReceivedSslError`: **always** `handler.cancel()`. No user override, no debug bypass in release.
- `WebChromeClient`: window creation per §7.3; permission requests denied; JS dialogs rendered natively with origin shown.
- `networkSecurityConfig`: cleartext disabled globally. Pin sets (§15), if a deployment requires them, are configured by the host app — outside `sea-core-android`.
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

> **Implementation status (v1 spike — iOS):** Both the **registration** (`navigator.credentials.create`) and **authentication** (`navigator.credentials.get`, usernameless/resident-key) ceremonies were validated **inside the embedded `WKWebView`** — the modal platform-authenticator sheet presents and completes, with no `ASWebAuthenticationSession` fallback — on the iOS **26.5 Simulator** with a validated `webcredentials:auth.bank.local` associated domain (developer mode). Two findings worth carrying forward:
> - **The embedded ceremony works; an earlier apparent "WKWebView can't do WebAuthn" failure was a *theme* bug, not a platform limit.** Keycloak's `webauthnRegister.js`/`webauthnAuthenticate.js` bare-import `"rfc4648"`, which the browser resolves only via the `<script type="importmap">` emitted by `base/login/template.ftl`. A custom theme that replaces `template.ftl` **must re-emit that import map**, or the module fails to load and the ceremony button silently does nothing — with no console error inside `ASWebAuthenticationSession`'s Safari view, so it mimics a platform failure. This is now the single most important gotcha for §18.2 themes.
> - **Conditional UI (autofill) is *not* used on iOS.** On Keycloak 26.6 the `enableWebAuthnConditionalUI` path is driven only by the deprecated `WebAuthnConditionalUIAuthenticator` (feature off by default), and autofill mediation is unreliable in `WKWebView` regardless. Passkey-first is therefore delivered as an **explicit primary CTA** (§10.3) that jumps to the passwordless authenticator, not as autofill — matching the engineering-note caveat that conditional UI "may not be available in WebViews."

### 10.3 Keycloak configuration

- WebAuthn Register (passwordless) required action + WebAuthn Passwordless authenticator in the browser flow.
- RP ID fixed to the auth domain; attestation conveyance `none` (or `indirect` if the bank requires authenticator attestation — decide per deployment); user verification `required`.
- Passkey-first login flow with password as fallback, per bank policy.

### 10.4 Fallback ceremony path (normative)

If the WebView environment cannot perform WebAuthn (capability probe at SEA startup + runtime failure detection):

1. SEA detects the condition (`webauthn_unavailable`) — either pre-flight (OS/WebView version below floor) or live (ceremony JS error surfaced via Keycloak's error redirect).
2. The **entire login attempt** is handed to the system path: `ASWebAuthenticationSession(url:callbackURLScheme:)` (iOS) / Android runner selects between two Custom Tabs mechanisms (Android, detailed below), using the same gateway-issued authorize URL. This path is RFC-8252-clean by definition.
3. The captured callback parameters flow into the same `onCaptured` contract (§6.3) and the same gateway submission (§6.4). Note: on this path the custom scheme *is* OS-dispatched, exposing the T9 hijack surface — accepted because the §6.4 triple binding (client secret + server-held verifier + native pre-auth session) renders a hijacked code worthless.
4. Telemetry records the fallback (`AUTH_WEBAUTHN_FALLBACK`) so rollout dashboards show the embedded-vs-fallback ratio per OS version.

This is the same machinery as the kill switch (§21) applied per-attempt.

> **Android runner selection (normative): Auth Tab preferred, Custom Tabs fallback.**
> `AuthTabIntent` (`androidx.browser.auth`, package `androidx.browser:browser:1.9.0`, stable — the experimental annotation was dropped in that release) is the Android analog of `ASWebAuthenticationSession`: it captures the callback redirect itself and returns it as an activity result, instead of relying on OS intent-dispatch of the custom scheme back into the app. Use it when available; otherwise degrade to plain Custom Tabs + an intent filter for the callback scheme (the mechanism previously documented as the sole Android path).
> - **Availability is a browser capability, not an Android OS version gate.** `AuthTabIntent` requires the handling browser to support it — Chrome 137+ is the current minimum; other Chromium-based browsers may follow. A device can be on the latest Android release and still lack support (old Chrome, or a non-Chrome default browser such as Samsung Internet or Firefox), while an older Android OS with a current Chrome supports it fine. `androidx.browser` itself only floors at API 23, which is not the binding constraint.
> - **Detection must happen at runtime**, not via any static OS-version check: resolve the target browser package (`CustomTabsClient.getPackageName`), then call `CustomTabsClient#isAuthTabSupported()` against it. Branch to `AuthTabIntent` on `true`, else the existing Custom Tabs + intent-filter path.
> - Both branches resolve through the same `onCaptured`/`onCancelled`/`onError` contract and the same §6.4 submission — this is a runner-internal implementation detail, invisible to the §4.3 API contract and to `sea-react-native`'s bridge surface.
> - Not yet implemented — `sea-core-android` doesn't exist in this repo yet. Recorded here so the decision is pinned before that workstream starts.

> **Explicit `authMode` override (normative, implemented — iOS).** Beyond the two automatic triggers in step 1 (pre-flight, runtime), `SEAConfig.authMode` lets a caller select the runner directly: `.embedded` (default) is the normal path described above; `.nativeBrowser` skips the embedded path unconditionally and enters the *same* `SEAFallbackAuthRunner` up front, regardless of `SEAWebAuthnCapability`'s verdict. This is not a WebAuthn-capability fallback and does not emit `AUTH_WEBAUTHN_FALLBACK` (which would misreport an explicit developer choice as an automatic OS-floor fallback on rollout dashboards); it still resolves through the same `onCaptured`/`onCancelled`/`onError` contract. Exposed through to `sea-react-native` as the `authMode` prop on `SecureAuthenticationView` (`'embedded' | 'nativeBrowser'`). Distinct from the host-SDK-level `EMBEDDED`/`SYSTEM_BROWSER` authMode described in §6 — that one bypasses SEACore entirely and runs the classic pre-SEA in-app-browser flow; `SEAConfig.authMode` stays inside SEACore either way.

> **Implementation status (v1 spike — iOS):**
> - The pre-flight probe (`SEAWebAuthnCapability`, step 1) is an OS-version floor comparison; the fallback path (`SEAFallbackEntryViewController` → `SEAFallbackAuthRunner` → `ASWebAuthenticationSession`) is wired and validated end-to-end, resolving through the same `onCaptured`/`onCancelled`/`onError` contract as the embedded path and emitting `AUTH_WEBAUTHN_FALLBACK`. The throwaway entry view controller **self-dismisses after any terminal outcome** (mirroring `SEAAuthViewController.dismissSelf`), so the fallback leaves no blank anchor on screen.
> - **Live (runtime) failure detection — step 1's "ceremony JS error" trigger — is deliberately *not* wired in v1.** The exact Keycloak error vocabulary is spike-provisional, and mis-routing a legitimate user cancel into an auto-restart is worse than not auto-falling-back. Because the embedded ceremony was validated as working (§10.2), the pre-flight OS floor is the only fallback trigger today. Wiring live detection (`SEAWebAuthnLiveFailure` predicate exists but is unused) is a follow-up once the error vocabulary is pinned on real devices.
> - The embedded path also **suppresses any post-terminal navigation/server error**: once capture fires, WebKit reporting the cancelled `bkrmob://` callback redirect as a non-`NSURLErrorCancelled` error (e.g. `NSURLErrorUnsupportedURL`) must never surface a spurious network-error modal over a successful login.

### 10.5 Why passkeys strengthen this design

WebAuthn credentials are origin-bound and verified against the associated-domain/asset-links chain, which cryptographically ties the ceremony to both the bank's domain **and** the genuine app package. A repackaged app fails asset-link validation and cannot exercise the user's passkey — directly mitigating T8/T11 and reinforcing the §3 argument.

---

## 11. Cookie and Session Management

### 11.1 Model: persistent app-scoped Keycloak SSO cookie

Selected model (per product decision): the Keycloak SSO session cookie (`KEYCLOAK_IDENTITY` et al.) persists in the WebView datastore across app restarts. Two session layers now exist, deliberately decoupled:

- **Keycloak SSO session** — cookie in the WebView datastore, governs whether re-authentication requires credentials.
- **Gateway Spring Session** — cookie in the native client's jar (§6.5), governs API access; its lifetime is typically much shorter.

Properties:

- Next login attempt (gateway session expired, SSO cookie valid): Bankerise SDK calls `/authorization/start` → SEA loads the authorize URL → Keycloak sees the SSO cookie → immediately redirects with a fresh code → §6.3 capture → §6.4 submission → fresh gateway session. **The user sees at most a flash of the loading state**; no credentials, near-silent re-auth.
- The SSO session is **app-scoped** (WKWebView default store is Safari-isolated; Android WebView cookies are app-private). No cross-app or system-browser SSO exists or is desired.
- Silent refresh: the same pass can run headlessly with `prompt=none` (passed via `/authorization/start`); `login_required` in the captured error params → surface interactive login.

### 11.2 Session timeline

```
First login
  /authorization/start → WebView → Keycloak login (passkey/password + MFA)
    → SSO cookie written to persistent WebView datastore
    → code captured → native submits to gateway → gateway session (native jar)

App restart (gateway session expired, SSO cookie within idle/max window)
  /authorization/start → WebView → SSO cookie recognized → code → gateway session
    (silent; optionally biometric-gated by the app shell before triggering)

SSO expiry / cookie cleared
  → full interactive login
```

Realm settings (dedicated mobile realm/client scope): SSO Session Idle and SSO Session Max define the re-auth cadence; set per bank policy (reference values: idle 30 days, max 90 days for retail; far stricter for corporate). Refresh token lifetimes ≤ SSO lifetimes; rotation on.

### 11.3 Logout (complete definition)

"Logout" in SEA means all of, atomically:

1. Native call to the gateway's logout endpoint → the gateway invalidates the Spring Session **and** performs RP-initiated OIDC logout against Keycloak with `id_token_hint` (tokens are server-side, so this is a pure server-to-server concern).
2. WebView datastore purge: `WKWebsiteDataStore.removeData(ofTypes: allWebsiteDataTypes)` / `CookieManager.removeAllCookies` + `WebStorage.deleteAllData` — kills the Keycloak SSO cookie.
3. Native cookie jar and secure-storage cleanup (gateway session cookie).
4. `AUTH_LOGOUT_COMPLETED` event.

Back-channel logout: because the OIDC client is the **gateway** — a server with a reachable endpoint — proper OIDC back-channel logout works natively: Keycloak calls the gateway's back-channel logout URI on admin-initiated session termination, the gateway invalidates the corresponding Spring Session, and the app's next API call returns 401 → app clears local state (steps 2–3) and shows login. This is a materially stronger story than mobile-public-client architectures, where the device is unreachable and back-channel logout degrades to polling; state it explicitly to auditors.

### 11.4 Cookie hardening

Keycloak issues its session cookies `HttpOnly; Secure; SameSite` — verified in the deployment checklist (§26). At-rest protection per §8.4 / §9.4. Device-sharing scenarios: the app shell requires its normal unlock (device credential / biometric) before SEA silent re-auth is triggered; a "switch user" action performs full logout (§11.3) first.

---

## 12. Keycloak Integration

### 12.1 Flow

Authorization Code + PKCE only. Client `bankerise-mobile`: **confidential** — the secret is held exclusively by the API Gateway (§6); PKCE S256 additionally enforced (`pkce.code.challenge.method=S256`) as defense in depth; exact-match redirect URI = the SEA callback scheme (e.g. `bankerise-auth://callback`); no implicit/hybrid, no direct access grants, consent off (first-party).

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
 |-- capture the callback (§6.3)
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

Default: **no bridge**. The callback capture (§6.3) makes a completion bridge unnecessary, and native chrome makes a close bridge unnecessary.

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

## 15. Certificate and Network Security (Out of SEA Scope)

TLS/certificate pinning is **not implemented by SEA**. It is a host-app and API Gateway responsibility: the Bankerise Mobile SDK's own native networking client (the one that talks to the gateway, §6.4) is where a pinning policy, if a deployment wants one, would be applied. SEA's own WebView traffic relies on default OS system-chain TLS validation only (`didReceive challenge → default handling`, `onReceivedSslError → cancel`, no override path, §8.2/§9.2) — no pin set is compiled into or evaluated by `sea-core-ios`/`sea-core-android`.

This section is retained as a scope pointer for cross-references elsewhere in this document (§3.4, §7.1, §8.2, §9.2, §26); it carries no implementation requirement for SEA.

---

## 16. Device Integrity and App Attestation (Out of SEA Scope)

Device integrity attestation (Play Integrity on Android, App Attest on iOS) is **not implemented by SEA**. It is a host-app and API Gateway responsibility: the Bankerise Mobile SDK generates and attaches attestation evidence to its own calls to the gateway (`/authorization/start` and/or code submission, §6.4), and the API Gateway is the sole enforcement point. SEA has no role in attestation key generation, assertion generation, evidence collection, or evidence validation.

This is already in place in the real deployment target: the Bankerise Mobile SDK performs app attestation against the gateway independently of SEA. This section is retained as a scope pointer for cross-references elsewhere in this document (§1.3, §3.2, §3.4, §4.2, §5, §6.1, §6.4, §17.3, §18.4, §23.2, §25, §26, §27, §28); it carries no implementation requirement for SEA.

---

## 17. Screen and Process Security

### 17.1 Capture protection

- Android: `FLAG_SECURE` on the SEA Activity/window → blocks screenshots, screen recording, and non-secure display mirroring; also blanks the recents/task-switcher thumbnail.
- iOS: task-switcher snapshot replaced with a branded cover view on `willResignActive`; `UIScreen.captured` monitored — active screen recording during SEA raises `AUTH_CAPTURE_DETECTED` and (policy per deployment) overlays a warning or blocks input. Screenshots cannot be blocked on iOS; `userDidTakeScreenshotNotification` is logged.

### 17.2 Overlay/tapjacking

- Android: `filterTouchesWhenObscured=true` on the WebView container; on supported OS versions, hidden-overlay touch policies enabled.

### 17.3 Root / jailbreak posture

- Detection via the existing Bankerise integrity module (native root/jailbreak checks). Play Integrity/App Attest corroboration (§16) is performed by the host app/gateway, outside SEA.
- Policy is deployment-configurable: `BLOCK` (default for high-security banks) | `WARN_AND_FLAG` (risk-engine signal) — never silent-allow.

---

## 18. UX Specification

### 18.1 Surface

Presentation: **bottom sheet** (Binance-style / in-app-browser-like), default and primary mode; `fullscreen` retained as an option.

```
        (dimmed app content behind)
+--------------------------------+
|  ⌢ grab handle                 |
|  Login to {bank}          ✕    |   ← native header, SDK-themed
+--------------------------------+
|                                |
|      Keycloak mobile theme     |
|      (login / passkey / MFA)   |
|                                |
+--------------------------------+
```

- iOS: `UISheetPresentationController` (large detent, grabber visible); Android: `BottomSheetDialogFragment` (expanded, no half-state during input). Keyboard resizes the sheet content, never hides fields.
- Swipe-to-dismiss = cancel (`onCancelled`), disabled while a ceremony/redirect is in flight.
- **Header title**: defaults to the current page's document title (driven by Keycloak, observed via `WKWebView.title` / `WebChromeClient.onReceivedTitle`); host may pin a static title (e.g. "Login to {bank}") via config. Title is display-only — sanitized, single line, never interpreted.
- **SDK-controlled appearance** (`SEAAppearance` in core config, exposed as a `appearance` prop): header background/text colors, accent color, sheet corner radius, grabber visibility, close icon tint, static title text, loading/error copy overrides. Colors/text only — no layout injection, and appearance never touches web content (§13; page look and feel remains the Keycloak theme's job).

Rules:

- No address bar, no progress URL, no share/refresh, no browser affordances of any kind.
- No external navigation ever visible to the user (§7.3), except the §12.4 external-tab case which presents as a system sheet and returns automatically.
- The WebView is pre-warmed so first paint is immediate (§22).

### 18.2 Keycloak mobile theme (required deliverable)

A dedicated `bankerise-mobile` Keycloak theme: mobile viewport, app brand tokens, light/dark following the app (`prefers-color-scheme` + theme param), RTL-correct Arabic layout, French/English variants via `ui_locales`, minimal chrome (no Keycloak header/footer), input types tuned for mobile keyboards, and passkey-first CTA layout. The theme is half of "feels native" — it ships with SEA v1, not later.

### 18.3 Loading states

Skeleton/branded spinner during initial load and during silent SSO re-auth (§11.1); the silent path should feel like an app splash, not a browser load.

### 18.4 Failure states

Native (not web) error surfaces for: offline, DNS/TLS failure, timeout (`timeoutMs`), server 5xx, and kill-switch fallback engagement — each with retry or fallback actions and localized copy (ar/fr/en). Gateway-reported attestation rejection surfaces through the Bankerise SDK's own error handling, not through SEA (§16).

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
AUTH_FAILED                  { code: network|timeout|invalid_authorize_url|server }
AUTH_TIMEOUT                 { stage }
AUTH_CAPTURE_DETECTED        { kind: recording|screenshot }
AUTH_LOGOUT_COMPLETED        { }
AUTH_KILLSWITCH_ENGAGED      { source: remote|local_failure }
```

### 20.2 Data rules

Never logged, in events or crash reports: usernames, passwords, tokens, codes, cookies, full URLs with query strings (log path class only), broker user identifiers. Hostnames hashed where needed for cardinality. Funnel dashboards per OS version are the early-warning system for platform breakage (feeds §21).

---

## 21. Kill Switch / Remote Fallback

- The kill switch is **gateway-driven**: `/authorization/start` returns `authMode: "EMBEDDED" | "SYSTEM_BROWSER"` alongside `redirect` (§6.1). **Absent field → `EMBEDDED`** (default). How the gateway decides — per platform, OS version, app version, client, or incident response — is gateway policy, out of SEA scope.
- The Bankerise Mobile SDK interprets `authMode` before instantiating anything: `EMBEDDED` → SEA; `SYSTEM_BROWSER` → the **classic in-app-browser authentication (the current pre-SEA flow)**, ASWebAuthenticationSession / Custom Tabs, with the same `redirectUrl` and the same callback → §6.4 submission. That path is standards-compliant, kept working, and release-gated (§24).
- Since `authMode` arrives per-attempt on an authenticated-TLS gateway call, no separate remote-config channel is needed for the switch; signing/scoping concerns collapse into ordinary gateway trust.
- Automatic local trigger: N consecutive `AUTH_FAILED(network|server)` on the embedded path within a session → SDK falls back to `SYSTEM_BROWSER` for the retry + telemetry (`AUTH_KILLSWITCH_ENGAGED{source: local_failure}`), regardless of the gateway's answer.
- Purpose: OS updates break WebView auth in the wild with some regularity; a gateway-side flip must resolve it in minutes across every bank deployment, without an app release.

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
- Capture/flow tests — SEA side: authorize-URL origin spoof rejected (§6.2); callback scheme intercepted in-process with instrumented proof of no OS dispatch; POST-redirect backstop exercised across WebView versions; error-shaped callbacks delivered. Gateway side: state mismatch, code replay (second submission must fail), PKCE downgrade, expired code, submission without pre-auth session cookie rejected (§6.4).
- TLS: invalid/self-signed/rotated-cert behavior, downgrade attempts (pin validation, where the host app pins, is out of SEA's test surface — §15).
- Capture/overlay: FLAG_SECURE verified, tapjacking test with overlay app.
- Pen test scope note for bank security teams: SEA + Keycloak mobile realm + gateway authorization endpoints (`/authorization/start`, code submission, logout), with §3 as the framing document.

### 23.3 Compatibility

Device-lab matrix over §25: WebAuthn ceremonies on each (OS, WebView) floor combination; annual re-validation at OS beta season (WebView auth is the component most likely to break in September).

Harnesses: the native demo apps (`demo-ios`, `demo-android`, §4.4) are the primary device-lab and spike vehicles — they exercise the cores with no RN in the loop. `demo-rn` validates only the bridge: prop marshalling, event delivery, threading (§4.7), and parity of the §7.1 API against the core contract.

---

## 24. CI/CD Guardrails

- The §13 forbidden list and §14 bridge maximum are enforced by lint rules failing the build.
- **Bridge purity lint** (§4.2, §7.4): `sea-react-native` sources may not import networking, crypto, storage, or WebView APIs; violations fail the build.
- **Lockstep release pipeline** (§4.6): one pipeline builds and publishes all three artifacts — signed XCFramework, AAR, npm package — atomically; if any artifact fails, no artifact ships.
- **Cross-artifact contract tests**: the §4.3 API contract is exercised directly against both cores (native test targets) and through the bridge via `demo-rn`, so contract drift between platforms or across the bridge is caught pre-release.
- Release gate: functional suite (§23.1) green on reference devices for both `EMBEDDED` and `SYSTEM_BROWSER` modes — the fallback path must never rot.
- Config-schema validation for §12.4 and §21 remote config.

---

## 25. Compatibility Matrix (to be finalized in platform spike)

| Capability | iOS floor | Android floor | Below floor behavior |
|---|---|---|---|
| Embedded WebView login (no passkeys) | TBD (spike) | TBD (spike) | n/a — baseline |
| Passkeys in embedded WebView | Validated on **iOS 26.5** (Simulator); registration + usernameless auth work embedded. Real floor TBD — needs older-OS device-lab run | TBD — WebView provider version with Credential Manager routing | §10.4 fallback ceremony |
| Conditional passkey UI (autofill suggestions) | **Not used** on iOS (§10.2) — deprecated on Keycloak 26.6 + unreliable in WKWebView; passkey-first delivered as explicit CTA instead | TBD | Modal ceremony only |

> The spike deliverable is this table with exact versions plus the measured embedded-passkey success rate per OS version from a device-lab run. §21 thresholds are then set from real data.
>
> **Spike progress (iOS):** the embedded passkey ceremony is confirmed working on iOS 26.5 (Simulator) with the `auth.bank.local` associated domain; `SEAWebAuthnCapability.embeddedSupportFloor` remains the provisional `16.0` pending a device-lab sweep of older OSes to set the real floor. The one hard prerequisite discovered — the theme `rfc4648` import map (§10.2) — is not an OS-version concern but a theme-packaging one.

---

## 26. Deployment Checklist

### iOS

- [ ] Associated Domains entitlement: `webcredentials:auth.bank.com` (per environment)
- [ ] `WKAppBoundDomains` in Info.plist: auth + approved broker domains
- [ ] ATS: no exceptions in release
- [ ] Backup exclusion of datastore paths verified

### Android

- [ ] `assetlinks.json` deployed and validated (package + all release signing certs, incl. Play App Signing key)
- [ ] `networkSecurityConfig`: cleartext off
- [ ] `allowBackup=false` + `dataExtractionRules` verified
- [ ] Minimum WebView provider floor enforced (in-app check → §21 fallback below floor)

### Host app / API Gateway (out of SEA scope, tracked here for deployment completeness)

- [ ] App Attest (iOS) / Play Integrity (Android) capability + backend validation configured, per §16
- [ ] TLS pin sets with expiry configured on the host app's networking client, per §15

### Keycloak

- [ ] Client `bankerise-mobile`: **confidential** (secret provisioned to the gateway only), PKCE S256 enforced, exact custom-scheme redirect URI, DAG off
- [ ] Session lifetimes per §11.2 policy
- [ ] WebAuthn policy configured per §10.3; RP ID correct per environment
- [ ] `bankerise-mobile` theme deployed (ar/fr/en, RTL, dark mode) and consuming `theme_*` params (§6.2)
- [ ] Cookies verified `HttpOnly; Secure; SameSite`
- [ ] Brute-force protection + WAF rules on auth endpoints
- [ ] Broker IdP policy config (§12.4) populated per environment

### Bankerise API Gateway

- [ ] Two-hop start sequence returning JSON (§6.1): `/authorization/start` → `{redirect, authMode?, provider}`; Spring Security filter → `{redirectUrl, provider}`; pre-auth session semantics verified
- [ ] `authMode` defaulting: absent → `EMBEDDED`; `SYSTEM_BROWSER` verified to launch the classic in-app-browser flow end-to-end (§21)
- [ ] Customized `OAuth2AuthorizationRequestResolver` with the §6.2 tier-3 parameter gate (pattern, reserved set, caps, telemetry on rejection)
- [ ] Code-submission endpoint validating state against the stored request; confidential exchange with server-held verifier
- [ ] Attestation validation wired per §16.2 policy tiers (host-app/gateway concern, out of SEA scope)
- [ ] Logout endpoint performing Spring Session invalidation + RP-initiated OIDC logout (§11.3)
- [ ] Back-channel logout URI registered in Keycloak and session-invalidation path tested (§11.3)
- [ ] Broker per-IdP policy config delivery (§12.4) wired and tested

---

## 27. Regulatory and Audit Notes

- §3 is the canonical answer to RFC 8252 findings; attach it to any bank security questionnaire.
- MASVS mapping: this spec addresses MASVS-AUTH, MASVS-NETWORK, MASVS-PLATFORM (WebView), MASVS-STORAGE (tokens/cookies), MASVS-RESILIENCE (§17; §16 resilience controls are host-app/gateway-owned). A full control-by-control traceability sheet is produced per deployment.
- Where PSD2/SCA or GCC central-bank e-banking guidelines apply: SCA is enforced by Keycloak flows (inherence via passkey user verification / biometric platform authenticator; possession via device-bound passkey, with device attestation as a host-app/gateway-owned reinforcement, §16); dynamic linking, where required, is a Keycloak custom-flow concern (§12.3), out of SEA scope but compatible.
- Data residency: SEA introduces no new data flows; all traffic terminates at the bank's Keycloak.

---

## 28. Future Extensions

- Biometric **step-up** authentication via `acr_values` + Keycloak step-up flows (transaction signing surfaces reusing SEA).
- **Device binding** of sessions: DPoP-bound tokens or mTLS at the token endpoint, keyed in Secure Enclave/StrongBox — natural hardening layer on §6.
- **App2app national eID** brokering (UAE Pass, PACI): extends §12.4 with a third mode (`APP2APP`) using verified app links back into the flow.
- **Continuous authentication** signals (behavioral, device posture) feeding the bank risk engine at token refresh.
- **Voice authentication integration**: Bankerise Voice Trust Engine (speaker verification + anti-spoofing) as a Keycloak authenticator for voice-channel step-up.
- **AI risk engine integration**: §20 event stream as a real-time feature source for adaptive authentication policies.
- **Additional wrappers over the same cores**: a Flutter plugin, and direct native-SDK distribution to banks with fully native apps — the cores are already the deliverable (§4.2), so this is a packaging and licensing exercise, not an engineering one.

---

*End of specification.*