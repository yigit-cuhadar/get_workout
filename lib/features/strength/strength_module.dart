import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../settings/domain/user_settings.dart';
import 'presentation/exercise_strength_cubit.dart';
import 'presentation/strength_list_cubit.dart';

/// Registers the strength pages. Needs `AuthModule`, `ExercisesModule`,
/// `ProgramsModule` (for the premium status) and `WorkoutModule`, which
/// keeps the stats.
class StrengthModule implements FeatureModule {
  const StrengthModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerFactory(
        () => StrengthListCubit(
          watchAuthUser: sl(),
          watchAllStats: sl(),
          catalogue: sl(),
        ),
      )
      // An exercise's id and the weight unit it opens in.
      ..registerFactoryParam<ExerciseStrengthCubit, String, WeightUnit>(
        (exerciseId, unit) => ExerciseStrengthCubit(
          exerciseId: exerciseId,
          watchAuthUser: sl(),
          watchStats: sl(),
          premium: sl(),
          unit: unit,
        ),
      );
  }
}
