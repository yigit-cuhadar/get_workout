# get_workout

Built with MobileAppForge. Work from the forge root (this repo is cloned at
`apps/get_workout` inside it) and follow the forge's `AGENTS.md`.

- State of the app and what to do next: `SPEC.md`.
- Run: `flutter run` (debug and profile use the dev Firebase project, release uses prod)
- Check before every commit: `dart format lib tool test && flutter analyze && flutter test`
- Widgetbook of the app's components: `cd widgetbook && dart run build_runner build -d && flutter run -d chrome`
- Admin panel (Flutter web, `lib/main_admin.dart`, code in `lib/admin/`): `flutter run -d chrome -t lib/main_admin.dart` against dev, with an account that has the admin claim; `tool/deploy_admin.sh <dev|prod>` deploys it to Firebase Hosting

Scripts in `tool/`; each prints or opens with its own usage. Those that reach a
Firebase project read a Google access token for it from `GOOGLE_ACCESS_TOKEN`.

- `validate_content.dart`: checks the exercises, programs and animations in `content/`
- `import_content.dart`: validates, then writes only what changed to a project
- `seed_demo.dart`: fills a dev account with demo data for store screenshots
- `set_admin.sh`: grants or revokes the admin claim
- `set_premium.sh`: grants or removes server-side Premium on a dev project
- `animation/`: the exercise animation tools (see SPEC › Exercise animations)
