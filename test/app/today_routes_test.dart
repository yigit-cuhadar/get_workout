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
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/features/today/presentation/today_page.dart';
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
];

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
  late EntitlementCubit entitlement;
  late GoRouter router;

  setUpAll(() {
    registerFallbackValue(upperLower);
    registerFallbackValue(MissedDayChoice.doToday);
  });

  Future<void> start(
    WidgetTester tester, {
    required ProgramListState programs,
    TodayVolumeState? volumeState,
  }) async {
    list = MockProgramListCubit();
    when(() => list.state).thenReturn(programs);
    workout = MockWorkoutCubit();
    when(() => workout.state)
        .thenReturn(const ActiveWorkoutState(status: WorkoutStatus.none));
    when(() => workout.access(any())).thenReturn(ProgramAccess.open);
    when(() => workout.startFree(any())).thenReturn(true);
    when(
      () => workout.startProgramDay(
        any(),
        any(),
        name: any(named: 'name'),
        language: any(named: 'language'),
      ),
    ).thenAnswer((_) async => (started: true, skipped: 0));
    // Never configured, so the premium status stays unknown.
    final store = FakePurchasesRepository(plans: fakePlans);
    entitlement = EntitlementCubit(
      configure: ConfigurePurchases(store),
      watchEntitlement: WatchEntitlement(store),
      identify: IdentifyPurchaser(store),
      reset: ResetPurchaser(store),
      refresh: RefreshEntitlement(store),
      getManagementUrl: GetManagementUrl(store),
    );
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
      });
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
          BlocProvider.value(value: entitlement),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    await entitlement.close();
    await sl.reset();
  });

  /// The stub page of [path] is on top.
  void expectAt(String path) => expect(find.text('at $path'), findsOneWidget);

  /// Scrolls the cards until [finder] is built and in view.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('the next workout', () {
    testWidgets('starts the next day through startProgramDay', (tester) async {
      await start(tester, programs: planned);

      expect(find.text('Upper Lower'), findsOneWidget);
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

      // The card's button, before the quick action of the same name.
      await tap(tester, find.text('Start empty workout').first);

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
    testWidgets('start an empty workout', (tester) async {
      await start(tester, programs: planned);

      await tap(tester, find.text('Start empty workout'));

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
}
