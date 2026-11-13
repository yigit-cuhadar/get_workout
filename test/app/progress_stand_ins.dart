import 'package:bloc_test/bloc_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/progress/presentation/progress_month_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _StrengthCubit extends MockCubit<ProgressStrengthState>
    implements ProgressStrengthCubit {}

class _MonthCubit extends MockCubit<ProgressMonthState>
    implements ProgressMonthCubit {}

class _CardioListCubit extends MockCubit<CardioListState>
    implements CardioListCubit {}

/// Registers the Progress tab's own cubits as stand-ins, for tests that
/// show the Progress tab without testing its widgets: no strength yet, the
/// month loading and, unless the test has its own, no cardio. Use with
/// `registerTodayStandIns` and `registerBodyListStandIn`.
void registerProgressStandIns() {
  sl
    ..registerFactory<ProgressStrengthCubit>(() {
      final cubit = _StrengthCubit();
      when(() => cubit.state).thenReturn(
        const ProgressStrengthState(status: ProgressStrengthStatus.ready),
      );
      return cubit;
    })
    ..registerFactory<ProgressMonthCubit>(() {
      final cubit = _MonthCubit();
      when(() => cubit.state)
          .thenReturn(ProgressMonthState(month: CalendarDate(2026, 11, 1)));
      return cubit;
    });
  if (!sl.isRegistered<CardioListCubit>()) {
    final cardio = _CardioListCubit();
    when(() => cardio.state).thenReturn(const CardioListState());
    sl.registerSingleton<CardioListCubit>(cardio);
  }
}
