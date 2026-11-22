# get_workout

Built with MobileAppForge. Work from the forge root (this repo is cloned at
`apps/get_workout` inside it) and follow the forge's `AGENTS.md`.

- State of the app and what to do next: `SPEC.md`.
- Run: `flutter run` (debug and profile use the dev Firebase project, release uses prod)
- Check before every commit: `dart format lib tool test && flutter analyze && flutter test`
- Widgetbook of the app's components: `cd widgetbook && dart run build_runner build -d && flutter run -d chrome`
- Grant or revoke the admin claim: `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) tool/set_admin.sh <project-id> <email> [--revoke]`
- Grant or remove server-side Premium on dev (writes `entitlements/{uid}`; refuses non `-dev` projects): `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) tool/set_premium.sh <project>-dev <uid> [days|off]`
- Seed a dev account with eight weeks of demo data for store screenshots (profile, an active Upper/Lower 4-Day copy, ~30 workouts with their stats, weigh-ins, measurement days, cardio, favourites; no photos; ids start with `demo_`, `--clear` removes them and keeps the profile): `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) dart run tool/seed_demo.dart --project getworkout-dev --uid <uid> [--dry-run] [--clear]`
- Validate content (exercises and programs, with a per-program summary): `dart run tool/validate_content.dart`
- Import content, exercises then programs (validates first, writes only changes): `GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) dart run tool/import_content.dart --project <project-id> [--dry-run] [--force]` (`--force` overwrites documents edited elsewhere, e.g. in the admin panel; a program's card and detail are written together or not at all)
- Admin panel (Flutter web, `lib/main_admin.dart`, code in `lib/admin/`): `flutter run -d chrome -t lib/main_admin.dart` (dev project); sign in with an account that has the admin claim
- Deploy the admin panel to Firebase Hosting: `tool/deploy_admin.sh <dev|prod>` (dev builds in profile mode against dev, prod in release mode against prod)
