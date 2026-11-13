import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'domain/progress_usecases.dart';
import 'presentation/progress_month_cubit.dart';
import 'presentation/progress_strength_cubit.dart';

/// Registers the Progress tab's own cubits; its other widgets use the
/// Today, body and cardio cubits. Needs `AuthModule`, `ExercisesModule`
/// and `WorkoutModule`.
class ProgressModule implements FeatureModule {
  const ProgressModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerFactory(() => WatchStrengthHighlights(sl()))
      ..registerFactory(() => WatchWorkoutCountInMonth(sl()))
      ..registerFactory(
        () => ProgressStrengthCubit(
          watchAuthUser: sl(),
          watchHighlights: sl(),
          catalogue: sl(),
        ),
      )
      ..registerFactory(
        () => ProgressMonthCubit(watchAuthUser: sl(), watchCount: sl()),
      );
  }
}
