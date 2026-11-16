import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'presentation/calendar_cubit.dart';

/// Registers the calendar. Needs `AuthModule`, `CardioModule`,
/// `ProgramsModule`, `WorkoutModule` and `HealthModule`, whose use cases it
/// reads.
class CalendarModule implements FeatureModule {
  const CalendarModule();

  @override
  void register(GetIt sl) {
    // One per calendar page; the parameter is the app's first weekday.
    sl.registerFactoryParam<CalendarCubit, int, void>(
      (firstWeekday, _) => CalendarCubit(
        firstWeekday: firstWeekday,
        watchAuthUser: sl(),
        watchWorkouts: sl(),
        watchCardio: sl(),
        watchPrograms: sl(),
        watchActiveProgram: sl(),
        // The workout pages open above the calendar, so it is there to
        // report their refused edits.
        watchRejectedEdits: sl(),
        getHealth: sl(),
      ),
    );
  }
}
