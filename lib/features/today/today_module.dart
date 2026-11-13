import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'presentation/today_steps_cubit.dart';
import 'presentation/today_volume_cubit.dart';
import 'presentation/today_week_cubit.dart';

/// Registers the Today tab's own cubits; its next workout is the Programs
/// tab's `ProgramListCubit`. Needs `AuthModule`, `CardioModule`,
/// `ExercisesModule`, `ProgramsModule`, `WorkoutModule`, `VolumeModule`
/// and `StepsModule`, whose use cases it reads.
class TodayModule implements FeatureModule {
  const TodayModule();

  @override
  void register(GetIt sl) {
    sl
      // One per Today page; the parameter is the app's first weekday.
      ..registerFactoryParam<TodayWeekCubit, int, void>(
        (firstWeekday, _) => TodayWeekCubit(
          firstWeekday: firstWeekday,
          watchAuthUser: sl(),
          watchWorkouts: sl(),
          watchCardio: sl(),
          watchPrograms: sl(),
          watchActiveProgram: sl(),
        ),
      )
      ..registerFactoryParam<TodayVolumeCubit, int, void>(
        (firstWeekday, _) => TodayVolumeCubit(
          firstWeekday: firstWeekday,
          watchAuthUser: sl(),
          watchVolume: sl(),
          catalogue: sl(),
        ),
      )
      ..registerFactory(
        () => TodayStepsCubit(getAccess: sl(), getTodaySteps: sl()),
      );
  }
}
