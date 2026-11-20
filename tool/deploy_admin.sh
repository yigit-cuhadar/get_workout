#!/usr/bin/env bash
# Builds the admin panel (lib/main_admin.dart) for the web and deploys it to
# Firebase Hosting of the dev project. prod's hosting serves the legal pages
# (target `legal`, see firebase.json).
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: tool/deploy_admin.sh dev

Builds in profile mode, which uses the dev Firebase project, and deploys to
getworkout-dev. Needs the Firebase CLI signed in to an account with access.
USAGE
  exit 2
}

[[ $# -eq 1 ]] || usage
case $1 in
  dev) project=getworkout-dev mode=--profile ;;
  *) usage ;;
esac

cd "$(dirname "$0")/.."
flutter build web -t lib/main_admin.dart "$mode"
firebase deploy --only hosting:admin --project "$project"
