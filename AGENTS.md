# get_workout

Built with MobileAppForge. Work from the forge root (this repo is cloned at
`apps/get_workout` inside it) and follow the forge's `AGENTS.md`.

- State of the app and what to do next: `SPEC.md`.
- Run: `flutter run` (debug and profile use the dev Firebase project, release uses prod)
- Check before every commit: `dart format lib tool test && flutter analyze && flutter test`
- Grant or revoke the admin claim: `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) tool/set_admin.sh <project-id> <email> [--revoke]`
- Import the exercise library (validates first, writes only changes): `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) dart run tool/import_content.dart --project <project-id> [--dry-run] [--force]` (`--force` overwrites exercises edited in the admin panel)
- Admin panel (Flutter web, `lib/main_admin.dart`, code in `lib/admin/`): `flutter run -d chrome -t lib/main_admin.dart` (dev project); sign in with an account that has the admin claim
- Deploy the admin panel to Firebase Hosting: `tool/deploy_admin.sh <dev|prod>` (dev builds in profile mode against dev, prod in release mode against prod)
