import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../features/calculators/calculators_module.dart';
import '../features/settings/settings_module.dart';
import 'app.dart';

/// Composition root: every feature module is registered here.
Future<void> bootstrap(AppEnv env, FirebaseOptions options) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebase(options: options, env: env);
  sl.registerSingleton<AppEnv>(env);
  registerModules(const [
    AuthModule(guestStart: true),
    SettingsModule(),
    CalculatorsModule(),
  ]);
  runApp(const App());
}
