#!/usr/bin/env bash
# Writes or removes a user's server-side entitlement on a dev project, so
# premium content can be demoed without a store purchase.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) \
         tool/set_premium.sh <project-id> <uid> [days|off]

Writes entitlements/<uid> with {"premium": true, "expiresAt": now + days}
(30 days by default), or deletes it with "off". Only for projects whose id
ends in -dev; in prod only the RevenueCat webhook writes entitlements. The
token needs Firestore write access to the project.

Either replaces the whole document, including what the webhook keeps to
order events (lastEventMs, lastEventId), so the next store event for the
user applies whatever its time.

This is the server's view only: the app's own Premium state comes from the
store (or the fake) and is not changed.
EOF
  exit 2
}

[[ $# -eq 2 || $# -eq 3 ]] || usage
project=$1
uid=$2
arg=${3:-30}

if [[ $project != *-dev ]]; then
  echo "Refusing $project: only projects ending in -dev." >&2
  exit 1
fi
[[ $uid =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Not a uid: $uid" >&2; exit 1; }
[[ $arg == off || $arg =~ ^[1-9][0-9]*$ ]] || usage
if [[ -z ${GOOGLE_ACCESS_TOKEN:-} ]]; then
  echo "GOOGLE_ACCESS_TOKEN is not set." >&2
  usage
fi
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }

url="https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents/entitlements/$uid"
body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

# Sends a request to the document and fails with the response on any
# status but 200. The token is passed through a process substitution so it
# never appears in the process list or in output.
call() {
  local method=$1 status
  shift
  status=$(curl -sS -o "$body_file" -w '%{http_code}' -X "$method" \
    -H @<(printf 'Authorization: Bearer %s\n' "$GOOGLE_ACCESS_TOKEN") \
    -H "x-goog-user-project: $project" \
    -H 'Content-Type: application/json' \
    "$@" "$url")
  if [[ $status != 200 ]]; then
    echo "$method entitlements/$uid failed with HTTP $status:" >&2
    cat "$body_file" >&2
    echo >&2
    exit 1
  fi
}

if [[ $arg == off ]]; then
  call DELETE
  echo "Removed the entitlement of $uid in $project."
  exit 0
fi

expires=$(jq -nr --argjson days "$arg" 'now + $days * 86400 | floor | todate')
call PATCH --data "$(jq -n --arg expires "$expires" '{fields: {
  premium: {booleanValue: true},
  expiresAt: {timestampValue: $expires}
}}')"
echo "Granted premium to $uid in $project until $expires."
