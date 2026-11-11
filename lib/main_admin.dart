// The admin panel (Flutter web): an internal English-only tool, so its
// strings are plain literals rather than entries of the app's ARB files.
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';

import 'admin/admin_bootstrap.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

/// Like the app: release builds use the prod Firebase project, debug and
/// profile builds use dev.
///
/// Run: `flutter run -d chrome -t lib/main_admin.dart`.
/// Deploy: `tool/deploy_admin.sh <dev|prod>`.
void main() => kReleaseMode
    ? bootstrapAdmin(AppEnv.prod, prod.DefaultFirebaseOptions.currentPlatform)
    : bootstrapAdmin(AppEnv.dev, dev.DefaultFirebaseOptions.currentPlatform);
