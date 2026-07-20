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

KC=(docker exec sea-keycloak /opt/keycloak/bin/kcadm.sh)
REALM=bankerise-mobile
SECRET=sea-dev-secret-do-not-use-in-production

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
  -s defaultLocale=en

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
    -s 'redirectUris=["bankerise-auth://callback"]' \
    -s 'attributes={"pkce.code.challenge.method":"S256"}'
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
    -s 'redirectUris=["bankerise-auth://callback"]' \
    -s 'attributes={"pkce.code.challenge.method":"S256"}'
fi

echo "==> user demo"
UID_=$("${KC[@]}" get users -r "${REALM}" -q username=demo \
         --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
if [[ -z "${UID_}" ]]; then
  "${KC[@]}" create users -r "${REALM}" \
    -s username=demo -s enabled=true -s emailVerified=true \
    -s email=demo@bank.local -s firstName=Demo -s lastName=User
  "${KC[@]}" set-password -r "${REALM}" --username demo --new-password demo123
fi

echo
echo "Done. Discovery:"
echo "  https://localhost/realms/${REALM}/.well-known/openid-configuration"
