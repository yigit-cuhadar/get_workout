import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/today/presentation/today_page.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart';
import '../features/workout/fixtures.dart' as fixtures show workout;
import '../features/workout/fixtures.dart' show exercise, lift;
import 'review_prompt_stand_in.dart';
import 'today_stand_ins.dart' show askedRestAlerts;

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class MockWeekCubit extends MockCubit<TodayWeekState>
    implements TodayWeekCubit {}

class MockWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class MockStepsCubit extends MockCubit<TodayStepsState>
    implements TodayStepsCubit {}

class MockEntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

const workoutOf = fixtures.workout;

CalendarDate d(int year, int month, int day) => CalendarDate(year, month, day);

/// Where Today's links lead; each a stub saying where it is, so this
/// tests Today's links, not the pages behind them.
const _targets = [
  Routes.calculators,
  Routes.catalogue,
  Routes.programGenerator,
  '/programs/p1',
  Routes.workout,
  Routes.paywall,
];

/// Two seconds of frames, enough for a route transition or a snack bar
/// to come in; bounded, so nothing that animates for ever can hang a
/// test.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final upperLower = program(id: 'p1');
  final sunday = d(2026, 11, 8);
  final active = ActiveProgram(
    programId: 'p1',
    schedule: const {1: 0, 4: 1},
    nextDayIndex: 1,
    nextDate: d(2026, 11, 12),
    startedAt: DateTime(2026, 11, 2),
  );
  final planned = ProgramListState(
    status: ProgramListStatus.ready,
    programs: [upperLower],
    active: active,
    nextDate: d(2026, 11, 12),
    premium: false,
  );
  final missed = ProgramListState(
    status: ProgramListStatus.ready,
    programs: [upperLower],
    active: active,
    nextDate: d(2026, 11, 16),
    missed: PlannedDay(
      date: d(2026, 11, 12),
      dayIndex: 1,
      status: PlannedStatus.missed,
    ),
    moveDate: d(2026, 11, 16),
    premium: false,
  );
  final week = TodayWeekState(
    today: d(2026, 11, 13),
    days: [for (var i = 0; i < 7; i++) sunday.addDays(i)],
    status: TodayWeekStatus.ready,
  );
  late MockProgramListCubit list;
  late MockWorkoutCubit workout;
  late MockStepsCubit steps;
  late GoRouter router;

  setUpAll(() {
    registerFallbackValue(upperLower);
    registerFallbackValue(MissedDayChoice.doToday);
  });

  Future<void> start(
    WidgetTester tester, {
    required ProgramListState programs,
    ActiveWorkoutState workoutState = const ActiveWorkoutState(
      status: WorkoutStatus.none,
    ),
    TodayStepsState stepsState = const TodayStepsState(
      status: TodayStepsStatus.ready,
      progress: StepGoalProgress(steps: 4000, goal: 10000),
    ),
    EntitlementState premium = const EntitlementUnknown(),
    ProgramAccess access = ProgramAccess.open,
  }) async {
    list = MockProgramListCubit();
    when(() => list.state).thenReturn(programs);
    workout = MockWorkoutCubit();
    when(() => workout.state).thenReturn(workoutState);
    when(() => workout.access(any())).thenReturn(access);
    when(() => workout.startFree(any())).thenReturn(true);
    when(
      () => workout.startProgramDay(
        any(),
        any(),
        name: any(named: 'name'),
        language: any(named: 'language'),
      ),
    ).thenAnswer((_) async => (started: true, skipped: 0));
    final entitlement = MockEntitlementCubit();
    when(() => entitlement.state).thenReturn(premium);
    final settings = MockSettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    steps = MockStepsCubit();
    when(() => steps.state).thenReturn(stepsState);
    when(() => steps.load(any())).thenAnswer((_) async {});
    sl
      ..registerSingleton<ProgramListCubit>(list)
      ..registerFactoryParam<TodayWeekCubit, int, void>((firstWeekday, _) {
        // English weeks start on Sunday.
        expect(firstWeekday, DateTime.sunday);
        final cubit = MockWeekCubit();
        when(() => cubit.state).thenReturn(week);
        return cubit;
      })
      ..registerFactory<TodayStepsCubit>(() => steps);
    registerReviewPrompt();
    router = GoRouter(
      initialLocation: Routes.today,
      routes: [
        GoRoute(path: Routes.today, builder: (_, _) => const TodayPage()),
        for (final path in _targets)
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('at $path')),
          ),
      ],
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ActiveWorkoutCubit>.value(value: workout),
          askedRestAlerts(),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MaterialApp.router(
          theme: ThemeData(
            extensions: AppPreset.shipped.lightTheme().extensions.values,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
  }

  tearDown(() => sl.reset());

  /// The stub page of [path] is on top.
  void expectAt(String path) => expect(find.text('at $path'), findsOneWidget);

  /// Scrolls the cards until [finder] is built and in view.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await settle(tester);
  }

  group('the next workout', () {
    testWidgets('starts the next day through startProgramDay', (tester) async {
      await start(tester, programs: planned);

      // The active program is the headline, its next day below.
      expect(find.text('Upper Lower'), findsOneWidget);
      expect(find.text('Next workout'), findsNothing);
      expect(find.textContaining('2 exercises · ~'), findsOneWidget);
      await tap(tester, find.text('Start Lower'));

      verify(
        () => workout.startProgramDay(
          upperLower,
          1,
          name: any(named: 'name'),
          language: 'en',
        ),
      ).called(1);
      expectAt(Routes.workout);
    });

    testWidgets('a locked premium copy opens the paywall, not the day', (
      tester,
    ) async {
      await start(
        tester,
        programs: planned,
        premium: const EntitlementInactive(),
        access: ProgramAccess.locked,
      );

      await tap(tester, find.text('Start Lower'));

      expectAt(Routes.paywall);
      verifyNever(
        () => workout.startProgramDay(
          any(),
          any(),
          name: any(named: 'name'),
          language: any(named: 'language'),
        ),
      );
    });

    testWidgets('opens its program', (tester) async {
      await start(tester, programs: planned);

      await tap(tester, find.text('Upper Lower'));

      expectAt('/programs/p1');
    });

    testWidgets('a missed day is answered here, not on Programs', (
      tester,
    ) async {
      await start(tester, programs: missed);
      when(() => list.resolveMissed(any())).thenAnswer((_) async {});

      await tap(tester, find.text('Do it today'));

      verify(() => list.resolveMissed(MissedDayChoice.doToday)).called(1);
      // Start comes back only once the day is answered.
      expect(find.text('Start Lower'), findsNothing);
    });

    testWidgets('a failed choice is reported by the prompt', (tester) async {
      await start(tester, programs: missed);
      when(() => list.resolveMissed(any())).thenAnswer((_) async {
        when(() => list.state).thenReturn(
          missed.copyWith(resolveFailure: () => const NetworkFailure('off')),
        );
      });

      await tap(tester, find.text('Skip'));

      expect(find.text('No internet connection'), findsOneWidget);
      verify(() => list.resolveFailureShown()).called(1);
    });

    testWidgets('without a program offers the catalogue', (tester) async {
      await start(
        tester,
        programs: const ProgramListState(status: ProgramListStatus.ready),
      );

      await tap(tester, find.text('See ready-made programs'));

      expectAt(Routes.catalogue);
    });

    testWidgets('without a program offers to just train', (tester) async {
      await start(
        tester,
        programs: const ProgramListState(status: ProgramListStatus.ready),
      );

      expect(find.text('Pick your first program'), findsOneWidget);
      await tap(tester, find.text('Start empty workout'));

      verify(() => workout.startFree('Workout')).called(1);
      expectAt(Routes.workout);
    });
  });

  testWidgets('every day offers an empty workout under the workout card', (
    tester,
  ) async {
    await start(tester, programs: planned);

    expect(find.text('Start Lower'), findsOneWidget);
    await tap(tester, find.text('Start empty workout'));

    verify(() => workout.startFree('Workout')).called(1);
    expectAt(Routes.workout);
  });

  testWidgets('with a workout in progress the empty workout asks first', (
    tester,
  ) async {
    await start(
      tester,
      programs: planned,
      workoutState: ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: workoutOf('w1', [
          exercise('squat', [lift(100, 5)]),
        ]),
      ),
    );

    await tap(tester, find.text('Start empty workout'));
    expect(find.text('A workout is in progress'), findsOneWidget);
    await tap(tester, find.text('Resume'));

    verifyNever(() => workout.startFree(any()));
    expectAt(Routes.workout);
  });

  testWidgets('the calculators card opens the calculators', (tester) async {
    await start(tester, programs: planned);

    await tap(tester, find.text('Calculators'));

    expectAt(Routes.calculators);
  });

  testWidgets('a rest day reads the steps for its walk', (tester) async {
    await start(
      tester,
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [upperLower],
        active: active,
        nextDate: d(2026, 11, 16),
        premium: false,
      ),
    );
    verify(() => steps.load(10000)).called(1);

    expect(find.text('6,000 steps to your goal'), findsOneWidget);
  });
}
