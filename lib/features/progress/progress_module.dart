import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import 'data/file_measurement_prompt_store.dart';
import 'domain/measurement_prompt.dart';
import 'domain/progress_usecases.dart';
import 'presentation/measurement_prompt_cubit.dart';
import 'presentation/progress_body_cubit.dart';
import 'presentation/progress_strength_cubit.dart';

/// Registers the Progress tab's own cubits; its other widgets use the
/// Today, body, cardio and programs cubits. Needs `AuthModule`,
/// `BodyModule`, `ExercisesModule`, `SettingsModule` and `WorkoutModule`.
class ProgressModule implements FeatureModule {
  const ProgressModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerFactory(() => WatchStrengthHighlights(sl()))
      ..registerLazySingleton<MeasurementPromptStore>(
        () => FileMeasurementPromptStore(getApplicationSupportDirectory),
      )
      ..registerFactory(() => LoadDismissedPrompt(sl()))
      ..registerFactory(() => DismissPrompt(sl()))
      ..registerFactory(
        () => ProgressStrengthCubit(
          watchAuthUser: sl(),
          watchHighlights: sl(),
          catalogue: sl(),
        ),
      )
      ..registerFactory(() => ProgressBodyCubit(bodyList: sl()))
      ..registerFactory(
        () => MeasurementPromptCubit(
          watchAuthUser: sl(),
          bodyList: sl(),
          settings: sl(),
          loadDismissed: sl(),
          dismiss: sl(),
        ),
      );
  }
}
