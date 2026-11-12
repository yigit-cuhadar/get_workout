import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'domain/volume_usecases.dart';
import 'presentation/volume_cubit.dart';

/// Registers weekly volume. Needs `AuthModule`, `ExercisesModule`,
/// `ProgramsModule` (for the premium status) and `WorkoutModule`.
class VolumeModule implements FeatureModule {
  const VolumeModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerFactory(() => WatchWeeklyVolume(sl()))
      // One per volume page; the parameter is the locale's first weekday.
      ..registerFactoryParam<VolumeCubit, int, void>(
        (firstWeekday, _) => VolumeCubit(
          firstWeekday: firstWeekday,
          watchAuthUser: sl(),
          watchVolume: sl(),
          catalogue: sl(),
          watchPremium: sl(),
        ),
      );
  }
}
