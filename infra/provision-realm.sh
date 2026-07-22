#!/usr/bin/env bash
# Provision the `bankerise-mobile` realm via Keycloak's own admin CLI.
#
# We provision rather than import a hand-written realm export: kcadm validates
# every field against the running server's schema, so the result is canonical
# by construction instead of hand-tuned until the importer stops complaining.
# `export-realm.sh` then dumps the canonical JSON for version control.
#
# Idempotent — safe to re-run. DEV ONLY: admin/admin, fixed client secret.
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required (brew install jq)." >&2; exit 1; }

KC=(docker exec sea-keycloak /opt/keycloak/bin/kcadm.sh)
REALM=bankerise-mobile
SECRET=sea-dev-secret-do-not-use-in-production
# WebAuthn RP ID must be the auth domain (§10.1/§10.3), not localhost, so it
# matches the iOS Associated Domain (webcredentials:auth.bank.local).
RP_ID=auth.bank.local
RP_NAME="Bankerise (dev)"
PASSKEY_FLOW="browser-passkey"

"${KC[@]}" config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin

echo "==> realm ${REALM}"
if "${KC[@]}" get "realms/${REALM}" >/dev/null 2>&1; then
  echo "    exists, updating"
  ACTION=update; TARGET="realms/${REALM}"
else
  ACTION=create; TARGET=realms
fi
"${KC[@]}" "${ACTION}" "${TARGET}" \
  -s "realm=${REALM}" \
  -s enabled=true \
  -s sslRequired=external \
  -s registrationAllowed=false \
  -s resetPasswordAllowed=true \
  -s loginWithEmailAllowed=true \
  -s bruteForceProtected=true \
  -s permanentLockout=false \
  -s maxFailureWaitSeconds=900 \
  -s failureFactor=5 \
  -s ssoSessionIdleTimeout=2592000 \
  -s ssoSessionMaxLifespan=7776000 \
  -s internationalizationEnabled=true \
  -s 'supportedLocales=["en","fr","ar"]' \
  -s defaultLocale=en \
  -s loginTheme=bankerise-mobile

# --- Confidential client (§12.1) — the production shape. -------------------
# The secret belongs to the API Gateway alone (§6). Nothing on the device
# ever holds it. Registered here so gateway integration can start immediately.
echo "==> client bankerise-mobile (confidential)"
CID=$("${KC[@]}" get clients -r "${REALM}" -q clientId=bankerise-mobile \
        --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
if [[ -z "${CID}" ]]; then
  "${KC[@]}" create clients -r "${REALM}" \
    -s clientId=bankerise-mobile \
    -s enabled=true \
    -s protocol=openid-connect \
    -s publicClient=false \
    -s "secret=${SECRET}" \
    -s standardFlowEnabled=true \
    -s implicitFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=false \
    -s consentRequired=false \
    -s 'redirectUris=["bkrmob://callback"]' \
    -s 'attributes={"pkce.code.challenge.method":"S256"}'
else
  # Re-run safety: pin the redirect URI even if the client pre-dates the
  # bkrmob:// scheme (was bankerise-auth://callback before iOS switched).
  "${KC[@]}" update "clients/${CID}" -r "${REALM}" \
    -s 'redirectUris=["bkrmob://callback"]'
fi

# --- Public client — DEV-ONLY SHORTCUT. ------------------------------------
# Lets the iOS demo drive the WebView surface end-to-end with NO gateway in
# the loop, which is exactly what Phase 1 needs. This does NOT reflect the
# production BFF architecture (§6), where the client is confidential and all
# token custody is server-side. Never provision this in a real environment.
echo "==> client sea-dev-public (DEV ONLY)"
PID=$("${KC[@]}" get clients -r "${REALM}" -q clientId=sea-dev-public \
        --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
if [[ -z "${PID}" ]]; then
  "${KC[@]}" create clients -r "${REALM}" \
    -s clientId=sea-dev-public \
    -s enabled=true \
    -s protocol=openid-connect \
    -s publicClient=true \
    -s standardFlowEnabled=true \
    -s implicitFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s consentRequired=false \
    -s 'redirectUris=["bkrmob://callback"]' \
    -s 'attributes={"pkce.code.challenge.method":"S256"}'
else
  # Re-run safety: pin the redirect URI even if the client pre-dates the
  # bkrmob:// scheme (was bankerise-auth://callback before iOS switched).
  "${KC[@]}" update "clients/${PID}" -r "${REALM}" \
    -s 'redirectUris=["bkrmob://callback"]'
fi

# --- WebAuthn passwordless / passkeys (spec §10.3) --------------------------
# RP ID is fixed to the auth domain, not localhost, so the associated-domain
# binding validated on the iOS side (webcredentials:auth.bank.local) lines up
# with the ceremony's relying party — see infra/nginx AASA location.
echo "==> required action: webauthn-register-passwordless"
"${KC[@]}" update "authentication/required-actions/webauthn-register-passwordless" -r "${REALM}" \
  -s alias=webauthn-register-passwordless \
  -s providerId=webauthn-register-passwordless \
  -s enabled=true \
  -s defaultAction=false

echo "==> realm WebAuthn Passwordless policy (RP ID ${RP_ID})"
"${KC[@]}" update "realms/${REALM}" \
  -s webAuthnPolicyPasswordlessRpEntityName="${RP_NAME}" \
  -s webAuthnPolicyPasswordlessRpId="${RP_ID}" \
  -s 'webAuthnPolicyPasswordlessSignatureAlgorithms=["ES256","RS256"]' \
  -s webAuthnPolicyPasswordlessAttestationConveyancePreference=none \
  -s webAuthnPolicyPasswordlessAuthenticatorAttachment=platform \
  -s webAuthnPolicyPasswordlessRequireResidentKey=Yes \
  -s webAuthnPolicyPasswordlessUserVerificationRequirement=required

# --- Passkey-first, password-fallback browser flow (spec §10.3) -------------
# Built as the canonical Keycloak "passwordless OR password" NESTED tree.
# The one rule that dominates this whole block: Keycloak refuses to run any
# level that mixes REQUIRED with ALTERNATIVE — it logs "REQUIRED and
# ALTERNATIVE elements at same level!", ignores the alternatives, and the
# flow throws AuthenticationFlowException (HTTP 400, no login form). So the
# passkey and password options must be ALTERNATIVE siblings under their OWN
# REQUIRED subflow, never siblings of the conditional-OTP subflow.
#
#   browser-passkey
#     Cookie                          ALTERNATIVE  (§11.1 silent SSO re-auth)
#     Identity Provider Redirector    ALTERNATIVE
#     forms                           ALTERNATIVE
#       passkey-or-password           REQUIRED     (single child of forms)
#         WebAuthn Passwordless        ALTERNATIVE (passkey-first)
#         password                     ALTERNATIVE (fallback)
#           Username Password Form      REQUIRED
#           conditional-otp             CONDITIONAL
#             Condition - user configured REQUIRED
#             OTP Form                    REQUIRED
#
# Rebuilt from scratch every run for a deterministic structure (kcadm has no
# "move execution" op, so surgically editing a copy of `browser` is worse).
# A flow bound as browserFlow can't be deleted, so we rebind to the built-in
# `browser` first — which also leaves a SAFE default bound if this script is
# interrupted mid-rebuild, rather than a half-built custom flow.
echo "==> browser-passkey authentication flow (passkey-first, password fallback)"
"${KC[@]}" update "realms/${REALM}" -s browserFlow=browser >/dev/null
BP_ID=$("${KC[@]}" get authentication/flows -r "${REALM}" \
  | jq -r '.[] | select(.alias=="'"${PASSKEY_FLOW}"'") | .id')
if [[ -n "${BP_ID}" ]]; then
  echo "    dropping existing '${PASSKEY_FLOW}' to rebuild cleanly"
  "${KC[@]}" delete "authentication/flows/${BP_ID}" -r "${REALM}"   # frees nested aliases too
fi

# Subflow aliases (hyphenated to dodge URL-encoding of spaces in the paths).
F_FORMS="${PASSKEY_FLOW}-forms"
F_POP="${PASSKEY_FLOW}-pop"      # passkey-or-password
F_PW="${PASSKEY_FLOW}-pw"        # password
F_OTP="${PASSKEY_FLOW}-otp"      # conditional OTP

# Build top-down. Executions land in creation order, so priorities come out
# already ordered within each parent — no raise-priority juggling needed.
"${KC[@]}" create authentication/flows -r "${REALM}" \
  -s alias="${PASSKEY_FLOW}" -s providerId=basic-flow -s topLevel=true -s builtIn=false
"${KC[@]}" create "authentication/flows/${PASSKEY_FLOW}/executions/execution" -r "${REALM}" -s provider=auth-cookie
"${KC[@]}" create "authentication/flows/${PASSKEY_FLOW}/executions/execution" -r "${REALM}" -s provider=identity-provider-redirector
"${KC[@]}" create "authentication/flows/${PASSKEY_FLOW}/executions/flow" -r "${REALM}" \
  -s alias="${F_FORMS}" -s type=basic-flow -s description="Passkey-first forms"
"${KC[@]}" create "authentication/flows/${F_FORMS}/executions/flow" -r "${REALM}" \
  -s alias="${F_POP}" -s type=basic-flow -s description="Passkey or password"
"${KC[@]}" create "authentication/flows/${F_POP}/executions/execution" -r "${REALM}" -s provider=webauthn-authenticator-passwordless
"${KC[@]}" create "authentication/flows/${F_POP}/executions/flow" -r "${REALM}" \
  -s alias="${F_PW}" -s type=basic-flow -s description="Password with optional OTP"
"${KC[@]}" create "authentication/flows/${F_PW}/executions/execution" -r "${REALM}" -s provider=auth-username-password-form
"${KC[@]}" create "authentication/flows/${F_PW}/executions/flow" -r "${REALM}" \
  -s alias="${F_OTP}" -s type=basic-flow -s description="Conditional OTP"
"${KC[@]}" create "authentication/flows/${F_OTP}/executions/execution" -r "${REALM}" -s provider=conditional-user-configured
"${KC[@]}" create "authentication/flows/${F_OTP}/executions/execution" -r "${REALM}" -s provider=auth-otp-form

# Fresh executions default to DISABLED, so every requirement is set explicitly.
# The top-level executions GET returns the whole nested tree with ids; the PUT
# to the same endpoint accepts nested ids. "priority" is ALWAYS carried through
# in the body — omitting it makes Keycloak 26.6 zero the execution's priority
# as a side effect, which would scramble the sibling order.
EXJSON=$("${KC[@]}" get "authentication/flows/${PASSKEY_FLOW}/executions" -r "${REALM}")
set_req() {  # $1 = providerId or subflow alias (displayName), $2 = requirement
  local key="$1" req="$2" id prio
  id=$(  echo "${EXJSON}" | jq -r --arg k "$1" 'first(.[] | select(.providerId==$k or .displayName==$k)) | .id')
  prio=$(echo "${EXJSON}" | jq -r --arg k "$1" 'first(.[] | select(.providerId==$k or .displayName==$k)) | .priority')
  "${KC[@]}" update "authentication/flows/${PASSKEY_FLOW}/executions" -r "${REALM}" \
    -b "{\"id\":\"${id}\",\"requirement\":\"${req}\",\"priority\":${prio}}"
}
set_req auth-cookie                          ALTERNATIVE
set_req identity-provider-redirector         ALTERNATIVE
set_req "${F_FORMS}"                          ALTERNATIVE
set_req "${F_POP}"                            REQUIRED
set_req webauthn-authenticator-passwordless  ALTERNATIVE
set_req "${F_PW}"                             ALTERNATIVE
set_req auth-username-password-form           REQUIRED
set_req "${F_OTP}"                            CONDITIONAL
set_req conditional-user-configured           REQUIRED
set_req auth-otp-form                          REQUIRED

echo "==> bind browserFlow -> ${PASSKEY_FLOW}"
"${KC[@]}" update "realms/${REALM}" -s "browserFlow=${PASSKEY_FLOW}"

echo "==> user demo"
UID_=$("${KC[@]}" get users -r "${REALM}" -q username=demo \
         --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
if [[ -z "${UID_}" ]]; then
  "${KC[@]}" create users -r "${REALM}" \
    -s username=demo -s enabled=true -s emailVerified=true \
    -s email=demo@bank.local -s firstName=Demo -s lastName=User
  "${KC[@]}" set-password -r "${REALM}" --username demo --new-password demo123
  # Pre-arm passkey enrollment (spec §10.3) so a freshly provisioned demo user
  # is prompted to register a passkey on first login — this makes the
  # passkey-first sign-in flow demoable out of the box (register once, then the
  # login page's "Sign in with Passkey" CTA works). Only on first creation, so
  # re-running provisioning never clobbers a user who already enrolled. Password
  # (demo123) always remains as the fallback.
  DEMO_ID=$("${KC[@]}" get users -r "${REALM}" -q username=demo \
              --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
  if [[ -n "${DEMO_ID}" ]]; then
    "${KC[@]}" update "users/${DEMO_ID}" -r "${REALM}" \
      -s 'requiredActions=["webauthn-register-passwordless"]'
  fi
fi

echo
echo "Done. Discovery:"
echo "  https://localhost/realms/${REALM}/.well-known/openid-configuration"
