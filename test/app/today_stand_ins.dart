import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _WeekCubit extends MockCubit<TodayWeekState> implements TodayWeekCubit {}

class _VolumeCubit extends MockCubit<TodayVolumeState>
    implements TodayVolumeCubit {}

class _StepsCubit extends MockCubit<TodayStepsState>
    implements TodayStepsCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _ProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

/// Registers the Today tab's cubits as stand-ins, for tests that land on
/// Today without testing it: the week and volume stay loading (no
/// spinner), steps have no health store, and the program list, unless
/// the test has its own, is ready and empty.
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
    })
    ..registerFactory<TodayStepsCubit>(() {
      final cubit = _StepsCubit();
      when(
        () => cubit.state,
      ).thenReturn(const TodayStepsState(status: TodayStepsStatus.unavailable));
      when(() => cubit.load(any())).thenAnswer((_) async {});
      return cubit;
    });
  if (!sl.isRegistered<ProgramListCubit>()) {
    final list = _ProgramListCubit();
    when(() => list.state)
        .thenReturn(const ProgramListState(status: ProgramListStatus.ready));
    sl.registerSingleton<ProgramListCubit>(list);
  }
}

/// The program list for the shell's `ProgramWritesNotice`, as the app
/// provides it; after [registerTodayStandIns] or the test's own.
BlocProvider<ProgramListCubit> programList() =>
    BlocProvider.value(value: sl<ProgramListCubit>());

/// The device defaults as the app's settings, for pages that read them
/// (the first weekday) in tests that do not test settings.
BlocProvider<SettingsCubit> defaultSettings() {
  final cubit = _SettingsCubit();
  when(() => cubit.state)
      .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
  return BlocProvider<SettingsCubit>.value(value: cubit);
}

/// A premium status that stays unknown, for Today's generator button in
/// tests without purchases.
BlocProvider<EntitlementCubit> unknownPremium() {
  final cubit = _EntitlementCubit();
  when(() => cubit.state).thenReturn(const EntitlementUnknown());
  return BlocProvider<EntitlementCubit>.value(value: cubit);
}
