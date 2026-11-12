import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
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
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart';
import '../features/workout/fixtures.dart' as fixtures show workout;
import '../features/workout/fixtures.dart' show exercise, lift;

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class MockWeekCubit extends MockCubit<TodayWeekState>
    implements TodayWeekCubit {}

class MockVolumeCubit extends MockCubit<TodayVolumeState>
    implements TodayVolumeCubit {}

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
  Routes.calendar,
  Routes.volume,
  Routes.cardioNew,
  Routes.historyNew,
  Routes.catalogue,
  Routes.programGenerator,
  '/programs/p1',
  Routes.workout,
  Routes.paywall,
  Routes.steps,
  Routes.calculators,
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
    weekdays: const [1, 4],
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
  // Quads 12 sets, glutes 6 as secondary.
  final volume = TodayVolumeState(
    weekStart: sunday,
    status: TodayVolumeStatus.ready,
    week: volumeWeeks(
      [
        workoutOf('w1', [
          exercise('squat', List.filled(12, lift(100, 5))),
        ], startedAt: DateTime(2026, 11, 10, 18)),
      ],
      first: sunday,
      count: 1,
      muscles: {
        'squat': (main: const [Muscle.quads], secondary: const [Muscle.glute]),
      },
    ).single,
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
    TodayVolumeState? volumeState,
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
    when(() => workout.state)
        .thenReturn(const ActiveWorkoutState(status: WorkoutStatus.none));
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
      ..registerFactoryParam<TodayVolumeCubit, int, void>((_, _) {
        final cubit = MockVolumeCubit();
        when(() => cubit.state).thenReturn(volumeState ?? volume);
        return cubit;
      })
      ..registerFactory<TodayStepsCubit>(() => steps);
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
          BlocProvider<EntitlementCubit>.value(value: entitlement),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MaterialApp.router(
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
      expect(find.text('Active program'), findsOneWidget);
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

    testWidgets('a missed day is resolved like on the Programs tab', (
      tester,
    ) async {
      await start(tester, programs: missed);
      when(() => list.resolveMissed(any())).thenAnswer((_) async {});

      await tap(tester, find.text('Do it today'));

      verify(() => list.resolveMissed(MissedDayChoice.doToday)).called(1);
      expect(find.text('Start Lower'), findsOneWidget);
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

      await tap(tester, find.text('Browse ready-made programs'));

      expectAt(Routes.catalogue);
    });

    testWidgets('without a program offers to just train', (tester) async {
      await start(
        tester,
        programs: const ProgramListState(status: ProgramListStatus.ready),
      );

      expect(find.text('Next workout'), findsOneWidget);
      expect(find.text('Active program'), findsNothing);
      // The card's button, before the quick action of the same name.
      await tap(tester, find.text('Free workout').first);

      verify(() => workout.startFree('Workout')).called(1);
      expectAt(Routes.workout);
    });
  });

  testWidgets('the week opens the calendar', (tester) async {
    await start(tester, programs: planned);

    await tap(tester, find.text('This week'));

    expectAt(Routes.calendar);
  });

  testWidgets('a day of the week opens the calendar', (tester) async {
    await start(tester, programs: planned);

    await tap(tester, find.text('10'));

    expectAt(Routes.calendar);
  });

  group('quick actions', () {
    testWidgets('start a free workout', (tester) async {
      await start(tester, programs: planned);

      await tap(tester, find.text('Free workout'));

      verify(() => workout.startFree('Workout')).called(1);
      expectAt(Routes.workout);
    });

    testWidgets('log cardio', (tester) async {
      await start(tester, programs: planned);

      await tap(tester, find.text('Log cardio'));

      expectAt(Routes.cardioNew);
    });

    testWidgets('add a past workout', (tester) async {
      await start(tester, programs: planned);

      await tap(tester, find.text('Add past workout'));

      expectAt(Routes.historyNew);
    });

    testWidgets('open the calculators', (tester) async {
      await start(tester, programs: planned);

      await tap(tester, find.text('Calculators'));

      expectAt(Routes.calculators);
    });
  });

  testWidgets('the volume card sums up the week and opens weekly volume', (
    tester,
  ) async {
    await start(tester, programs: planned);

    await reveal(tester, find.text('1 in the band · 1 below · 0 above'));
    expect(find.text('Quads'), findsOneWidget);
    await tap(tester, find.text('Sets this week'));

    expectAt(Routes.volume);
  });

  testWidgets('a volume card that failed leaves the next workout', (
    tester,
  ) async {
    await start(
      tester,
      programs: planned,
      volumeState: TodayVolumeState(
        weekStart: sunday,
        status: TodayVolumeStatus.failure,
        failure: const NetworkFailure('off'),
      ),
    );

    expect(find.text('Start Lower'), findsOneWidget);
    await reveal(tester, find.text("Couldn't load your workouts"));
  });

  group('steps', () {
    testWidgets('today against the goal, opening the Steps page', (
      tester,
    ) async {
      await start(tester, programs: planned);
      verify(() => steps.load(10000)).called(1);

      await reveal(tester, find.text('4,000 of 10,000'));
      expect(find.text('6,000 to go'), findsOneWidget);
      await tap(tester, find.text('Steps'));

      expectAt(Routes.steps);
    });

    testWidgets('not set up: an entry to the Steps page', (tester) async {
      await start(
        tester,
        programs: planned,
        stepsState: const TodayStepsState(status: TodayStepsStatus.setUp),
      );

      await tap(tester, find.text('See your steps'));

      expectAt(Routes.steps);
    });

    testWidgets('no card without a health store', (tester) async {
      await start(
        tester,
        programs: planned,
        stepsState: const TodayStepsState(status: TodayStepsStatus.unavailable),
      );
      await reveal(tester, find.text('Sets this week'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await settle(tester);

      expect(find.text('Steps'), findsNothing);
    });
  });
}
