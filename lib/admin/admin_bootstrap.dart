import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import 'access/access_module.dart';
import 'admin_app.dart';
import 'exercises/exercise_admin_module.dart';
import 'programs/program_admin_module.dart';

/// Composition root of the admin panel; the mobile app's is
/// `lib/app/bootstrap.dart`, and the two share no registrations.
Future<void> bootstrapAdmin(AppEnv env, FirebaseOptions options) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Not forge_firebase's initFirebase: Crashlytics has no web support, and
  // an internal tool collects no analytics.
  await Firebase.initializeApp(options: options);
  registerModules(const [
    AuthModule(),
    AdminAccessModule(),
    ExerciseAdminModule(),
    ProgramAdminModule(),
  ]);
  runApp(AdminApp(env: env, projectId: options.projectId));
}
