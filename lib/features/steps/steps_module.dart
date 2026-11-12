import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import 'data/file_steps_prompt.dart';
import 'domain/steps_prompt.dart';
import 'domain/steps_usecases.dart';
import 'presentation/steps_cubit.dart';

/// The platform health store, except in debug and profile builds on a
/// platform without one (neither iOS nor Android), which read the fake.
/// The iOS simulator has HealthKit, without steps unless added in Health.
HealthModule healthModule({
  required TargetPlatform platform,
  required bool release,
}) {
  final hasStore =
      platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  return hasStore || release
      ? const HealthModule()
      : HealthModule.fake(FakeHealthSteps());
}

/// Registers the Steps page and [GetTodaySteps] for the Today tab. Needs
/// `HealthModule`.
class StepsModule implements FeatureModule {
  const StepsModule();

  @override
  void register(GetIt sl) {
    sl
      // App support files are private and not shown to the user.
      ..registerLazySingleton<StepsPrompt>(
        () => const FileStepsPrompt(getApplicationSupportDirectory),
      )
      ..registerFactory(() => GetStepsAccess(sl(), sl()))
      ..registerFactory(() => AllowStepsAccess(sl(), sl()))
      ..registerFactory(() => GetStepsHistory(sl()))
      ..registerFactory(() => GetTodaySteps(sl()))
      ..registerFactory(
        () => StepsCubit(
          getAccess: sl(),
          allowAccess: sl(),
          getHistory: sl(),
          openSettings: sl(),
        ),
      );
  }
}
