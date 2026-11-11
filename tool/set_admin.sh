#!/usr/bin/env bash
# Grants or revokes the admin custom claim of a Firebase Auth user, keeping
# the user's other custom claims. See usage() for when a change takes effect.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) \
         tool/set_admin.sh <project-id> <email> [--revoke]

Sets {"admin": true} in the custom claims of the Firebase Auth user with that
email, or removes it with --revoke. Other custom claims are kept. The token
needs Firebase Auth admin access to the project.

Claims travel in the user's ID token, so a change is not instant: a grant
takes effect once the user signs in again or refreshes the token, and a
revoke only when the token refreshes (up to an hour later).
EOF
  exit 2
}

[[ $# -eq 2 || ($# -eq 3 && $3 == --revoke) ]] || usage
project=$1
email=$2
revoke=false
[[ $# -eq 3 ]] && revoke=true

if [[ -z ${GOOGLE_ACCESS_TOKEN:-} ]]; then
  echo "GOOGLE_ACCESS_TOKEN is not set." >&2
  usage
fi
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }

api="https://identitytoolkit.googleapis.com/v1/projects/$project"
body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

# POSTs JSON to accounts:<method> and prints the response body. The token is
# passed through a process substitution so it never appears in the process
# list or in output.
call() {
  local method=$1 data=$2 status
  status=$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
    -H @<(printf 'Authorization: Bearer %s\n' "$GOOGLE_ACCESS_TOKEN") \
    -H "x-goog-user-project: $project" \
    -H 'Content-Type: application/json' \
    --data "$data" "$api/accounts:$method")
  if [[ $status != 200 ]]; then
    echo "accounts:$method failed with HTTP $status:" >&2
    cat "$body_file" >&2
    echo >&2
    exit 1
  fi
  cat "$body_file"
}

lookup=$(call lookup "$(jq -n --arg email "$email" '{email: [$email]}')")
count=$(jq '.users // [] | length' <<<"$lookup")
if [[ $count -eq 0 ]]; then
  echo "No user with email $email in project $project." >&2
  exit 1
fi
if [[ $count -gt 1 ]]; then
  echo "More than one user with email $email in project $project." >&2
  exit 1
fi

uid=$(jq -r '.users[0].localId' <<<"$lookup")
claims=$(jq -c --argjson revoke "$revoke" '
  (.users[0].customAttributes // "{}" | fromjson)
  | if $revoke then del(.admin) else .admin = true end' <<<"$lookup")

call update "$(jq -n --arg uid "$uid" --arg claims "$claims" \
  '{localId: $uid, customAttributes: $claims}')" >/dev/null

if $revoke; then
  echo "Revoked admin for $email ($uid). Custom claims now: $claims"
else
  echo "Granted admin to $email ($uid). Custom claims now: $claims"
fi
