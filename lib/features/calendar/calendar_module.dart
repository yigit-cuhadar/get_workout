import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'presentation/calendar_cubit.dart';
import 'presentation/calendar_list_cubit.dart';

/// Registers the calendar. Needs `AuthModule`, `CardioModule`,
/// `ProgramsModule` and `WorkoutModule`, whose use cases it reads.
class CalendarModule implements FeatureModule {
  const CalendarModule();

  @override
  void register(GetIt sl) {
    sl
      // One per calendar page; the parameter is the locale's first weekday.
      ..registerFactoryParam<CalendarCubit, int, void>(
        (firstWeekday, _) => CalendarCubit(
          firstWeekday: firstWeekday,
          watchAuthUser: sl(),
          watchWorkouts: sl(),
          watchCardio: sl(),
          watchPrograms: sl(),
          watchActiveProgram: sl(),
        ),
      )
      // The workout pages open above the calendar, so it is there to report
      // their refused edits.
      ..registerFactoryParam<CalendarListCubit, int, void>(
        (firstWeekday, _) => CalendarListCubit(
          firstWeekday: firstWeekday,
          watchAuthUser: sl(),
          watchHistory: sl(),
          watchWorkouts: sl(),
          watchCardio: sl(),
          watchPrograms: sl(),
          watchActiveProgram: sl(),
          watchRejectedEdits: sl(),
        ),
      );
  }
}
