import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../features/account/account_module.dart';
import '../features/calculators/calculators_module.dart';
import '../features/calendar/calendar_module.dart';
import '../features/cardio/cardio_module.dart';
import '../features/exercises/exercises_module.dart';
import '../features/generator/generator_module.dart';
import '../features/notifications/notifications_module.dart';
import '../features/profile/profile_module.dart';
import '../features/programs/programs_module.dart';
import '../features/settings/settings_module.dart';
import '../features/today/today_module.dart';
import '../features/steps/steps_module.dart';
import '../features/volume/volume_module.dart';
import '../features/strength/strength_module.dart';
import '../features/workout/workout_module.dart';
import '../features/subscription/subscription_module.dart';
import 'app.dart';

/// Composition root: every feature module is registered here.
Future<void> bootstrap(AppEnv env, FirebaseOptions options) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: options);
  await AccountModule.clearDeletedAccountCache();
  // Never forge_firebase's initFirebase, here or in any other entry point
  // (e.g. a future FCM background handler): it turns Analytics and
  // Crashlytics on before the user agreed. See SPEC's open questions.
  final telemetry = await AccountModule.startTelemetry(env);
  sl.registerSingleton<AppEnv>(env);
  registerModules([
    const AuthModule(guestStart: true),
    const SettingsModule(),
    const NotificationsModule(),
    const ProfileModule(),
    const CardioModule(),
    const CalculatorsModule(),
    const ExercisesModule(),
    const ProgramsModule(
      completedDays: WorkoutModule.completedDays,
      premium: SubscriptionModule.premiumStatus,
      showPremium: SubscriptionModule.showPaywall,
    ),
    const GeneratorModule(),
    const WorkoutModule(),
    AccountModule(telemetry: telemetry),
    const VolumeModule(),
    const StrengthModule(),
    const CalendarModule(),
    const TodayModule(),
    healthModule(platform: defaultTargetPlatform, release: kReleaseMode),
    const StepsModule(),
    SubscriptionModule(
      backend: purchasesBackend(
        platform: defaultTargetPlatform,
        release: kReleaseMode,
      ),
    ),
  ]);
  runApp(const App());
}
