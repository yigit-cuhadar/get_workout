import 'package:bloc_test/bloc_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _WeekCubit extends MockCubit<TodayWeekState> implements TodayWeekCubit {}

class _VolumeCubit extends MockCubit<TodayVolumeState>
    implements TodayVolumeCubit {}

class _ProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

/// Registers the Today tab's cubits as stand-ins that stay loading, for
/// tests that land on Today without testing it; the program list too
/// unless the test has its own.
void registerTodayStandIns() {
  final monday = CalendarDate(2026, 11, 9);
  sl
    ..registerFactoryParam<TodayWeekCubit, int, void>((_, _) {
      final cubit = _WeekCubit();
      when(() => cubit.state).thenReturn(
        TodayWeekState(
          today: monday,
          days: [for (var i = 0; i < 7; i++) monday.addDays(i)],
        ),
      );
      return cubit;
    })
    ..registerFactoryParam<TodayVolumeCubit, int, void>((_, _) {
      final cubit = _VolumeCubit();
      when(() => cubit.state).thenReturn(TodayVolumeState(weekStart: monday));
      return cubit;
    });
  if (!sl.isRegistered<ProgramListCubit>()) {
    final list = _ProgramListCubit();
    when(() => list.state).thenReturn(const ProgramListState());
    sl.registerSingleton<ProgramListCubit>(list);
  }
}
