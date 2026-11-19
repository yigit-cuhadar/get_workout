import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/today/presentation/today_page.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:get_workout/features/today/presentation/widgets/rest_day_card.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class _WeekCubit extends MockCubit<TodayWeekState> implements TodayWeekCubit {}

class _StepsCubit extends MockCubit<TodayStepsState>
    implements TodayStepsCubit {}

class _ProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _WorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

void main() {
  // Friday 13 November 2026, in a week from Monday 9.
  final friday = CalendarDate(2026, 11, 13);
  final monday = CalendarDate(2026, 11, 9);
  final days = [for (var i = 0; i < 7; i++) monday.addDays(i)];
  final upperLower = program(id: 'p1');
  final active = ActiveProgram(
    programId: 'p1',
    schedule: const {1: 0, 5: 1},
    nextDayIndex: 1,
    nextDate: friday,
    startedAt: DateTime(2026, 11, 2),
  );
  const done = WorkoutSet(reps: 8, done: true);
  const open = WorkoutSet(reps: 8);
  const bench = WorkoutExercise(
    exerciseId: 'a',
    name: 'Bench press',
    loggingType: LoggingType.weightReps,
  );

  setUpAll(() => registerFallbackValue(MissedDayChoice.skip));

  late _WeekCubit week;
  late _StepsCubit steps;
  late _ProgramListCubit programs;
  late _WorkoutCubit workout;

  ProgramListState plan({
    CalendarDate? nextDate,
    bool finished = false,
    PlannedDay? missed,
    CalendarDate? moveDate,
    ActiveProgram? activeProgram,
  }) => ProgramListState(
    status: ProgramListStatus.ready,
    programs: [upperLower],
    active: activeProgram ?? active,
    finished: finished,
    nextDate: nextDate,
    missed: missed,
    moveDate: moveDate,
    premium: false,
  );

  TodayWeekState weekOf({
    TodayWeekStatus status = TodayWeekStatus.ready,
    List<Workout> workouts = const [],
  }) => TodayWeekState(
    today: friday,
    days: days,
    status: status,
    entries: {
      if (workouts.isNotEmpty)
        friday: [for (final workout in workouts) WorkoutEntry(workout)],
    },
  );

  setUp(() {
    week = _WeekCubit();
    steps = _StepsCubit();
    programs = _ProgramListCubit();
    workout = _WorkoutCubit();
    when(() => week.state).thenReturn(weekOf());
    when(() => steps.state).thenReturn(
      const TodayStepsState(
        status: TodayStepsStatus.ready,
        progress: StepGoalProgress(steps: 6240, goal: 10000),
      ),
    );
    when(() => steps.load(any())).thenAnswer((_) async {});
    when(() => programs.state).thenReturn(plan(nextDate: friday));
    when(programs.refreshNow).thenReturn(null);
    when(() => workout.state)
        .thenReturn(const ActiveWorkoutState(status: WorkoutStatus.none));
    sl
      ..registerFactoryParam<TodayWeekCubit, int, void>((_, _) => week)
      ..registerFactory<TodayStepsCubit>(() => steps)
      ..registerSingleton<ProgramListCubit>(programs);
  });

  tearDown(sl.reset);

  /// Today at its route, every other route showing its location.
  Future<void> pumpToday(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 4800)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final entitlement = _EntitlementCubit();
    when(() => entitlement.state).thenReturn(const EntitlementUnknown());
    Widget location(BuildContext _, GoRouterState state) =>
        Text('at ${state.uri.path}');
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (_, _) => const TodayPage(),
          routes: [GoRoute(path: 'workouts/:id', builder: location)],
        ),
        GoRoute(
          path: '/:a',
          builder: location,
          routes: [
            GoRoute(
              path: ':b',
              builder: location,
              routes: [
                GoRoute(
                  path: ':c',
                  builder: location,
                  routes: [GoRoute(path: ':d', builder: location)],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
          BlocProvider<ActiveWorkoutCubit>.value(value: workout),
        ],
        child: MaterialApp.router(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a training day offers its day, an empty workout and the '
      'calculators; the week, its sets and steps are on Progress', (
    tester,
  ) async {
    await pumpToday(tester);

    expect(find.text('Start Lower'), findsOneWidget);
    expect(find.text('Fri, Nov 13'), findsOneWidget);
    expect(find.text('Start empty workout'), findsOneWidget);
    expect(find.text('Pick exercises as you go'), findsOneWidget);
    expect(find.widgetWithText(ForgeChip, 'Calories'), findsOneWidget);
    expect(find.text('This week'), findsNothing);
    expect(find.text('Sets this week'), findsNothing);
    expect(find.text('3,760 to go'), findsNothing);

    await tester.tap(find.text('Upper Lower'));
    await tester.pumpAndSettle();
    expect(find.text('at /programs/p1'), findsOneWidget);
  });

  testWidgets('a rest day offers recovery, the next day early and cardio', (
    tester,
  ) async {
    when(() => programs.state)
        .thenReturn(plan(nextDate: CalendarDate(2026, 11, 16)));
    await pumpToday(tester);

    expect(find.byType(RestDayCard), findsOneWidget);
    expect(find.text('Next: Lower, Mon, Nov 16'), findsOneWidget);
    expect(find.text('3,760 steps to your goal'), findsOneWidget);
    expect(find.text('Start Lower early'), findsOneWidget);
    expect(find.text('Start Lower'), findsNothing);
    // Once, as Today's own row.
    expect(find.text('Start empty workout'), findsOneWidget);

    await tester.tap(find.text('Log cardio'));
    await tester.pumpAndSettle();
    expect(find.text('at /progress/cardio/new'), findsOneWidget);
  });

  testWidgets('a workout done today shows over the next day', (tester) async {
    when(() => programs.state)
        .thenReturn(plan(nextDate: CalendarDate(2026, 11, 16)));
    when(() => week.state).thenReturn(
      weekOf(
        workouts: [
          Workout(
            id: 'w5',
            startedAt: DateTime(2026, 11, 13, 7),
            finishedAt: DateTime(2026, 11, 13, 7, 52),
            programId: 'p1',
            dayIndex: 0,
            name: 'Upper Lower · Upper',
            exercises: [
              bench.copyWith(
                sets: const [
                  WorkoutSet(type: SetType.warmup, reps: 10, done: true),
                  done,
                  done,
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await pumpToday(tester);

    expect(find.text('Done today · Upper'), findsOneWidget);
    expect(find.text('2 sets · 52 min'), findsOneWidget);
    expect(find.text('Next: Lower'), findsOneWidget);
    expect(find.byType(RestDayCard), findsNothing);

    await tester.tap(find.text('See summary'));
    await tester.pumpAndSettle();
    expect(find.text('at /today/workouts/w5'), findsOneWidget);

    // On top of Today: Back returns there.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Done today · Upper'), findsOneWidget);
  });

  testWidgets('a missed day is answered in its band, without Start', (
    tester,
  ) async {
    when(() => programs.state).thenReturn(
      plan(
        nextDate: friday,
        missed: PlannedDay(
          date: CalendarDate(2026, 11, 9),
          dayIndex: 1,
          status: PlannedStatus.missed,
        ),
        moveDate: CalendarDate(2026, 11, 16),
      ),
    );
    when(() => programs.resolveMissed(any())).thenAnswer((_) async {});
    await pumpToday(tester);

    expect(find.text('You missed Lower on Mon, Nov 9'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Start Lower'), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    verify(() => programs.resolveMissed(MissedDayChoice.skip)).called(1);
  });

  testWidgets('a running workout shows where it is and its time', (
    tester,
  ) async {
    when(() => workout.state).thenReturn(
      ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: Workout(
          id: 'w6',
          startedAt: DateTime.now(),
          name: 'Workout',
          exercises: [
            bench.copyWith(sets: const [done, done, done]),
            bench.copyWith(sets: const [done, open]),
            bench.copyWith(sets: const [open]),
          ],
        ),
      ),
    );
    await pumpToday(tester);

    expect(find.text('Workout in progress'), findsOneWidget);
    expect(find.text('Exercise 2 of 3 · 4 sets done'), findsOneWidget);
    expect(find.text('Resume workout'), findsOneWidget);
    expect(find.text('Start Lower'), findsNothing);
  });

  testWidgets('a running program day is titled by its day', (tester) async {
    when(() => workout.state).thenReturn(
      ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: Workout(
          id: 'w7',
          startedAt: DateTime.now(),
          programId: 'p1',
          dayIndex: 1,
          // As startProgramDay names it.
          name: 'Upper Lower · Lower',
          exercises: [
            bench.copyWith(sets: const [open]),
          ],
        ),
      ),
    );
    await pumpToday(tester);

    expect(find.text('Lower'), findsOneWidget);
    expect(find.text('Upper Lower · Lower'), findsNothing);
  });

  testWidgets('without a program, the ready-made ones and an empty workout; '
      'the generator is on Programs', (tester) async {
    when(() => programs.state).thenReturn(
      const ProgramListState(status: ProgramListStatus.ready, premium: false),
    );
    await pumpToday(tester);

    expect(find.text('Pick your first program'), findsOneWidget);
    expect(find.text('See ready-made programs'), findsOneWidget);
    expect(find.text('Generate a program'), findsNothing);
    expect(find.text('Start empty workout'), findsOneWidget);

    await tester.tap(find.text('See ready-made programs'));
    await tester.pumpAndSettle();
    expect(find.text('at /programs/catalogue'), findsOneWidget);
  });

  testWidgets('saved programs but none active: see your programs', (
    tester,
  ) async {
    when(() => programs.state).thenReturn(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [upperLower, upperLower],
        premium: false,
      ),
    );
    await pumpToday(tester);

    expect(find.text('Choose a program to start'), findsOneWidget);
    expect(
      find.text(
        'You have 2 saved programs. Start one to set your training days.',
      ),
      findsOneWidget,
    );
    expect(find.text('Generate a program'), findsNothing);

    await tester.tap(find.text('See your programs'));
    await tester.pumpAndSettle();
    expect(find.text('at /programs'), findsOneWidget);
  });

  testWidgets('a finished program names itself', (tester) async {
    when(() => programs.state).thenReturn(plan(finished: true));
    await pumpToday(tester);

    expect(find.text('Program finished'), findsOneWidget);
    expect(
      find.text(
        'Upper Lower is done. A new plan sets your training days and fills '
        'Today.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the workout card loads on its own; the rest need nothing', (
    tester,
  ) async {
    when(() => week.state).thenReturn(weekOf(status: TodayWeekStatus.loading));
    when(() => steps.state).thenReturn(const TodayStepsState());
    when(() => programs.state).thenReturn(const ProgramListState());
    await pumpToday(tester);

    expect(find.byType(SkeletonBar), findsWidgets);
    expect(find.text('Next workout'), findsOneWidget);
    expect(find.text('Start empty workout'), findsOneWidget);
    expect(find.widgetWithText(ForgeChip, 'Plates'), findsOneWidget);
  });
}
