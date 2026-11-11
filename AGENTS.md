# get_workout

Built with MobileAppForge. Work from the forge root (this repo is cloned at
`apps/get_workout` inside it) and follow the forge's `AGENTS.md`.

- State of the app and what to do next: `SPEC.md`.
- Run: `flutter run` (debug and profile use the dev Firebase project, release uses prod)
- Check before every commit: `dart format lib tool test && flutter analyze && flutter test`
- Grant or revoke the admin claim: `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) tool/set_admin.sh <project-id> <email> [--revoke]`
- Import the exercise library (validates first, writes only changes): `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) dart run tool/import_content.dart --project <project-id> [--dry-run]`
