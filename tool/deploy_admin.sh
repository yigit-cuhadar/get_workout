#!/usr/bin/env bash
# Builds the admin panel (lib/main_admin.dart) for the web and deploys it to
# the project's Firebase Hosting target `admin`: getworkout-dev.web.app on
# dev, getworkout-admin.web.app on prod (whose default site serves the legal
# pages, target `legal`).
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: tool/deploy_admin.sh <dev|prod>

dev builds in profile mode, which uses the dev Firebase project; prod builds
in release mode, which uses prod. Needs the Firebase CLI signed in to an
account with access.
USAGE
  exit 2
}

[[ $# -eq 1 ]] || usage
case $1 in
  dev) project=getworkout-dev mode=--profile ;;
  prod) project=getworkout-prod mode=--release ;;
  *) usage ;;
esac

cd "$(dirname "$0")/.."
flutter build web -t lib/main_admin.dart "$mode"
firebase deploy --only hosting:admin --project "$project"
