import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';
import 'package:forge_remote_config/forge_remote_config.dart';

import '../features/body/body_module.dart';
import '../features/account/account_module.dart';
import '../features/calculators/calculators_module.dart';
import '../features/calendar/calendar_module.dart';
import '../features/cardio/cardio_module.dart';
import '../features/exercises/exercises_module.dart';
import '../features/generator/generator_module.dart';
import '../features/notifications/notifications_module.dart';
import '../features/profile/profile_module.dart';
import '../features/programs/programs_module.dart';
import '../features/progress/progress_module.dart';
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
  final telemetry = await initFirebase(options: options, env: env);
  await AccountModule.clearDeletedAccountCache();
  const RemoteConfigModule(
    defaults: SubscriptionModule.remoteConfigDefaults,
    backend: FirebaseRemoteConfigBackend(
      // Debug builds pick up a console change on the second launch after it.
      minimumFetchInterval: kReleaseMode
          ? Duration(hours: 12)
          : Duration(minutes: 1),
    ),
  ).register(sl);
  // Local only (the fetch runs in the background), alongside the restore. A
  // failure is logged and leaves the defaults.
  final remoteConfig = sl<RemoteConfigRepository>().initialize();
  await telemetry.restore(FirebaseAuth.instance.currentUser?.uid);
  await remoteConfig;
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
    const ProgressModule(),
    healthModule(platform: defaultTargetPlatform, release: kReleaseMode),
    const StepsModule(),
    const BodyModule(),
    SubscriptionModule(
      backend: purchasesBackend(
        platform: defaultTargetPlatform,
        release: kReleaseMode,
      ),
    ),
  ]);
  runApp(const App());
}
