import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../features/calculators/calculators_module.dart';
import '../features/cardio/cardio_module.dart';
import '../features/exercises/exercises_module.dart';
import '../features/profile/profile_module.dart';
import '../features/programs/programs_module.dart';
import '../features/settings/settings_module.dart';
import '../features/workout/workout_module.dart';
import '../features/subscription/subscription_module.dart';
import 'app.dart';

/// Composition root: every feature module is registered here.
Future<void> bootstrap(AppEnv env, FirebaseOptions options) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebase(options: options, env: env);
  sl.registerSingleton<AppEnv>(env);
  registerModules([
    const AuthModule(guestStart: true),
    const SettingsModule(),
    const ProfileModule(),
    const CardioModule(),
    const CalculatorsModule(),
    const ExercisesModule(),
    const ProgramsModule(
      completedDays: WorkoutModule.completedDays,
      premium: SubscriptionModule.premiumStatus,
      showPremium: SubscriptionModule.showPaywall,
    ),
    const WorkoutModule(),
    SubscriptionModule(
      backend: purchasesBackend(
        platform: defaultTargetPlatform,
        release: kReleaseMode,
      ),
    ),
  ]);
  runApp(const App());
}
