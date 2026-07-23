#!/usr/bin/env bash
# Re-arm passkey (WebAuthn passwordless) enrollment for a demo user.
#
# WHY THIS EXISTS
# The `webauthn-register-passwordless` required action is what makes Keycloak
# show the passkey-enrollment page after a password login. provision-realm.sh
# pre-arms it for a freshly provisioned user, but it is CONSUMED the first time
# the user enrolls. After that (or after you delete the passkey credential from
# the admin UI, which does NOT re-arm it) a password login completes straight
# to the bkrmob:// callback with no enrollment step — and SEA correctly captures
# the code and dismisses. Re-running this restores the enrollment prompt.
#
# Deleting the passkey in the iOS Passwords app / on-device is NOT enough: the
# gate is this server-side required action, so reset it here.
#
# USAGE:  infra/rearm-passkey-enrollment.sh [username]   (default: demo)
#
# After running: log out / "Purge web data" in the demo app to drop the WebView
# SSO cookie, then "Start login" and sign in with the password — the enrollment
# page will appear and persist.
set -euo pipefail

REALM=bankerise-mobile
USERNAME="${1:-demo}"
KC=(docker exec sea-keycloak /opt/keycloak/bin/kcadm.sh)

"${KC[@]}" config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin >/dev/null

USER_ID="$("${KC[@]}" get users -r "$REALM" -q "username=${USERNAME}" --fields id --format csv --noquotes 2>/dev/null | head -n1)"
if [[ -z "${USER_ID}" ]]; then
  echo "No user '${USERNAME}' in realm '${REALM}'." >&2
  exit 1
fi

"${KC[@]}" update "users/${USER_ID}" -r "$REALM" \
  -s 'requiredActions=["webauthn-register-passwordless"]'

echo "Re-armed webauthn-register-passwordless for '${USERNAME}' (${USER_ID})."
echo "Now log out / Purge web data in the demo, then Start login and enter the password."
