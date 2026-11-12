import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'presentation/calendar_cubit.dart';

/// Registers the calendar. Needs `AuthModule`, `CardioModule`,
/// `ProgramsModule` and `WorkoutModule`, whose use cases it reads.
class CalendarModule implements FeatureModule {
  const CalendarModule();

  @override
  void register(GetIt sl) {
    sl.registerFactory(
      () => CalendarCubit(
        watchAuthUser: sl(),
        watchWorkouts: sl(),
        watchCardio: sl(),
        watchPrograms: sl(),
        watchActiveProgram: sl(),
      ),
    );
  }
}
