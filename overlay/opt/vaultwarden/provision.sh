#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# BEST-EFFORT decoy-vault provisioning for Vaultwarden.
#
# Goal: 'worker' can AUTOFILL the fake-site logins but cannot reveal/copy the
# password, via the Bitwarden Organization "Hide Passwords" collection
# permission (readOnly + hidePasswords on the collection MEMBERSHIP).
#
# ⚠️  READ THIS FIRST — two hard truths from research:
#   1. "Hide Passwords" is a CLIENT-SIDE SOFT CONTROL, not a security boundary.
#      Autofill still delivers the cleartext password to worker's browser, so a
#      technical user can read it via devtools (input.value), the sync response,
#      or `bw` with their own creds. It stops casual viewing/copying only.
#   2. Headless provisioning is fragile: the `bw` CLI CANNOT create an
#      Organization (no `bw create organization`) and recent CLI versions have
#      `--raw`/confirm bugs. So this script does the bw-SCRIPTABLE parts and
#      leaves Organization creation as a one-time manual web-vault step.
#
# Requires Vaultwarden v1.35.0+ (fixes the 'edit, hidden passwords' bypass).
# ============================================================================
#
# PREREQUISITES (do once, as the OWNER, in the web vault at http://localhost:8080):
#   a) Create your owner account (Create account).
#   b) Create a new Organization (e.g. "Decoys"). Copy its Organization ID
#      (Settings → Organization info, or the URL).
#   c) Create the 'worker' account too (sign up worker@local / a password) so it
#      has an encryption keypair to share against.
#   d) Install the Bitwarden CLI 'bw' and point it at this server:
#        npm i -g @bitwarden/cli            # (pin a known-good version if needed)
#        bw config server http://localhost:8080
#
# Then run, as the owner:
#   ORG_ID=<org-uuid> OWNER_EMAIL=you@local OWNER_PW='...' \
#   WORKER_EMAIL=worker@local ./provision.sh
#
# If anything here fails, fall back to the fully-manual flow in docs/HARDENING.md
# (import fake-sites.json → invite worker → confirm → tick "Hide Passwords").

: "${ORG_ID:?set ORG_ID to your Organization UUID (create the org in the web vault first)}"
: "${OWNER_EMAIL:?set OWNER_EMAIL}"; : "${OWNER_PW:?set OWNER_PW}"
: "${WORKER_EMAIL:?set WORKER_EMAIL}"
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v bw >/dev/null || { echo "bw CLI not found — see prerequisites"; exit 1; }
bw config server "${BW_SERVER:-http://localhost:8080}" >/dev/null

echo "==> login as owner"
BW_SESSION="$(bw login "$OWNER_EMAIL" "$OWNER_PW" --raw 2>/dev/null || true)"
[ -n "${BW_SESSION:-}" ] || BW_SESSION="$(bw unlock "$OWNER_PW" --raw)"   # if already logged in
export BW_SESSION
bw sync

echo "==> create collection 'Worker Logins' (idempotent)"
COL_ID="$(bw list org-collections --organizationid "$ORG_ID" 2>/dev/null \
  | jq -r '.[] | select(.name=="Worker Logins") | .id' | head -n1)"
if [ -z "$COL_ID" ]; then
  COL_ID="$(bw get template org-collection \
    | jq --arg o "$ORG_ID" '.name="Worker Logins" | .organizationId=$o | .users=[] | .groups=[]' \
    | bw encode | bw create org-collection --organizationid "$ORG_ID" | jq -r '.id')"
fi
echo "    collection: $COL_ID"

echo "==> create decoy login items in the collection (from fake-sites.json)"
jq -c '.items[]' "$HERE/fake-sites.json" | while read -r it; do
  name="$(echo "$it" | jq -r '.name')"
  bw list items --organizationid "$ORG_ID" 2>/dev/null | jq -e --arg n "$name" '.[]|select(.name==$n)' >/dev/null && continue
  bw get template item \
    | jq --arg o "$ORG_ID" --arg c "$COL_ID" --argjson src "$it" \
        '.type=1 | .name=$src.name | .notes=$src.notes | .organizationId=$o
         | .collectionIds=[$c] | .login=$src.login' \
    | bw encode | bw create item >/dev/null
  echo "    + $name"
done

echo "==> confirm 'worker' org membership + set Hide Passwords"
MEMBER_ID="$(bw list org-members --organizationid "$ORG_ID" 2>/dev/null \
  | jq -r --arg e "$WORKER_EMAIL" '.[] | select(.email==$e) | .id' | head -n1)"
if [ -z "$MEMBER_ID" ]; then
  echo "    worker not invited yet — invite worker to the org in the web vault, then re-run." >&2
  exit 2
fi
bw confirm org-member "$MEMBER_ID" --organizationid "$ORG_ID" 2>/dev/null || true
bw sync
# readOnly + hidePasswords = "View items, hidden passwords": autofill works, reveal blocked.
bw get org-collection "$COL_ID" --organizationid "$ORG_ID" \
  | jq --arg m "$MEMBER_ID" '.users=[{id:$m, readOnly:true, hidePasswords:true, manage:false}]' \
  | bw encode | bw edit org-collection "$COL_ID" --organizationid "$ORG_ID" >/dev/null

echo "==> done. Verify as 'worker': the fake logins autofill but the password is masked."
echo "    Reminder: this is a soft/UX control, not a hard security boundary."
bw logout >/dev/null 2>&1 || true
