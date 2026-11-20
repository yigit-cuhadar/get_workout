import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_detail_page.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _ListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _DetailCubit extends MockCubit<ProgramDetailState>
    implements ProgramDetailCubit {}

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _ModelCubit extends MockCubit<BodyModelState> implements BodyModelCubit {}

class _WorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

void main() {
  // Wednesday 11 November 2026.
  final today = CalendarDate(2026, 11, 11);
  final upperLower = program(id: 'p1', lengthWeeks: 8);
  final active = ActiveProgram(
    programId: 'p1',
    schedule: const {1: 0, 4: 1},
    nextDayIndex: 1,
    nextDate: CalendarDate(2026, 11, 12),
    startedAt: DateTime(2026, 11, 2),
  );

  late _ListCubit list;
  late _DetailCubit detail;
  late int paywalls;

  setUpAll(() {
    registerFallbackValue(MissedDayChoice.skip);
    registerFallbackValue(program());
  });

  ProgramListState ready({
    List<Program>? programs,
    ActiveProgram? activeProgram,
    bool finished = false,
    PlannedDay? missed,
    List<PlannedDay> weekPlan = const [],
    bool? premium = true,
  }) => ProgramListState(
    status: ProgramListStatus.ready,
    programs: programs ?? [upperLower],
    active: activeProgram,
    weekPlan: weekPlan,
    finished: finished,
    today: today,
    week: activeProgram == null ? null : 2,
    nextDate: finished || activeProgram == null
        ? null
        : CalendarDate(2026, 11, 12),
    missed: missed,
    moveDate: missed == null ? null : CalendarDate(2026, 11, 16),
    premium: premium,
  );

  setUp(() {
    paywalls = 0;
    list = _ListCubit();
    detail = _DetailCubit();
    when(() => detail.state).thenReturn(const ProgramDetailState());
    when(() => detail.stop()).thenAnswer((_) async {});
    when(() => detail.delete()).thenAnswer((_) async {});
    when(() => detail.start(any())).thenAnswer((_) async {});
    when(() => list.resolveMissed(any())).thenAnswer((_) async {});
    sl
      ..registerSingleton<ProgramListCubit>(list)
      ..registerSingleton(PremiumPrompt((_) => paywalls++))
      ..registerFactoryParam<ProgramDetailCubit, String, void>(
        (_, _) => detail,
      );
  });

  tearDown(sl.reset);

  Future<void> pump(WidgetTester tester, ProgramListState state) async {
    tester.view
      ..physicalSize = const Size(1200, 4800)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => list.state).thenReturn(state);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(const CatalogueLoading());
    final model = _ModelCubit();
    when(() => model.state).thenReturn(const BodyModelLoading());
    when(model.load).thenAnswer((_) async {});
    final workout = _WorkoutCubit();
    when(() => workout.state)
        .thenReturn(const ActiveWorkoutState(status: WorkoutStatus.none));
    when(() => workout.access(any())).thenReturn(ProgramAccess.locked);
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final entitlement = _EntitlementCubit();
    when(() => entitlement.state).thenReturn(const EntitlementUnknown());
    Widget location(BuildContext _, GoRouterState state) =>
        Text('at ${state.uri.path}');
    final router = GoRouter(
      initialLocation: '/programs/p1',
      routes: [
        GoRoute(
          path: '/programs/p1',
          builder: (_, _) => const ProgramDetailPage(id: 'p1'),
        ),
        GoRoute(
          path: '/:a',
          builder: location,
          routes: [
            GoRoute(
              path: ':b',
              builder: location,
              routes: [GoRoute(path: ':c', builder: location)],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<BodyModelCubit>.value(value: model),
          BlocProvider<ActiveWorkoutCubit>.value(value: workout),
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
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

  // The weekly sets card shimmers while it loads, which never settles.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  Finder options() => find.bySemanticsLabel('Program options');

  testWidgets('a program not running: its size, Not active and Start', (
    tester,
  ) async {
    await pump(tester, ready());

    expect(find.text('8 weeks · 2 days'), findsOneWidget);
    expect(find.text('Not active'), findsOneWidget);
    expect(find.text('Start program'), findsOneWidget);
    expect(find.text('Weekly sets in this program'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Day 1 · Upper'), findsOneWidget);
    expect(find.text('Day 2 · Lower'), findsOneWidget);
  });

  testWidgets('Start asks for the training days, then starts', (tester) async {
    await pump(tester, ready());

    await tester.tap(find.text('Start program'));
    // The sheet rises in the frames after it opens.
    await settle(tester);
    await settle(tester);
    expect(find.text('Training days'), findsOneWidget);
    // The suggestion is one weekday per day in order, so it opens Simple.
    expect(find.text('Pick the 2 weekdays you train on.'), findsOneWidget);
    await tester.tap(find.text('Start program').last);
    await settle(tester);
    verify(() => detail.start(const {1: 0, 4: 1})).called(1);
  });

  testWidgets('another active program is replaced only once confirmed', (
    tester,
  ) async {
    final arms = program(id: 'p2', name: 'Arms');
    await pump(
      tester,
      ready(
        programs: [upperLower, arms],
        activeProgram: ActiveProgram(
          programId: 'p2',
          schedule: const {1: 0, 4: 1},
          nextDayIndex: 0,
          nextDate: CalendarDate(2026, 11, 12),
          startedAt: DateTime(2026, 11, 2),
        ),
      ),
    );

    await tester.tap(find.text('Start program'));
    await settle(tester);
    expect(find.text('Replace your active program?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Training days'), findsNothing);
    verifyNever(() => detail.start(any()));
  });

  testWidgets('the active program: its days, next day, week over a bar in '
      'weeks, Change days and Stop; Today starts the day', (tester) async {
    await pump(
      tester,
      ready(
        activeProgram: active,
        weekPlan: [
          PlannedDay(
            date: CalendarDate(2026, 11, 9),
            dayIndex: 0,
            status: PlannedStatus.done,
          ),
          PlannedDay(
            date: CalendarDate(2026, 11, 12),
            dayIndex: 1,
            status: PlannedStatus.planned,
          ),
        ],
      ),
    );

    expect(find.text('Mon, Thu'), findsOneWidget);
    expect(find.textContaining('Active'), findsNothing);
    expect(find.text('Next: Lower'), findsOneWidget);
    expect(find.text('Thu, Nov 12'), findsOneWidget);
    expect(find.text('Week 2 of 8'), findsOneWidget);
    expect(find.text('1 of 2 days this week'), findsOneWidget);
    final bar = tester.widget<Progress>(find.byType(Progress));
    expect(bar.segments, 8);
    expect(bar.value, closeTo((1 + 1 / 2) / 8, 1e-9));
    expect(find.text('Start Lower'), findsNothing);
    expect(find.text('Change days'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('Stop asks first', (tester) async {
    await pump(tester, ready(activeProgram: active));

    await tester.tap(find.text('Stop'));
    await settle(tester);
    expect(find.text('Stop this program?'), findsOneWidget);
    await tester.tap(find.text('Stop program'));
    await settle(tester);
    verify(() => detail.stop()).called(1);
  });

  testWidgets('a days mismatch is said over the progress', (tester) async {
    await pump(
      tester,
      ready(
        activeProgram: ActiveProgram(
          programId: 'p1',
          // Made for three days; the program now has two.
          schedule: const {1: 0, 4: 2},
          nextDayIndex: 1,
          nextDate: CalendarDate(2026, 11, 12),
          startedAt: DateTime(2026, 11, 2),
        ),
      ),
    );

    expect(
      find.text(
        'The program now has 2 days. Change your training days to '
        'match.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a missed day is answered first; no Start', (tester) async {
    final missed = PlannedDay(
      date: CalendarDate(2026, 11, 9),
      dayIndex: 1,
      status: PlannedStatus.missed,
    );
    await pump(tester, ready(activeProgram: active, missed: missed));

    expect(find.text('Start Lower'), findsNothing);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Do it today'), findsOneWidget);
    expect(find.text('Move to Monday'), findsOneWidget);
    expect(find.text('Change days'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    verify(() => list.resolveMissed(MissedDayChoice.skip)).called(1);
  });

  testWidgets('a finished program runs again or leads to a new one', (
    tester,
  ) async {
    await pump(tester, ready(activeProgram: active, finished: true));

    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Run it again'), findsOneWidget);
    expect(find.text('New program'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Change days'), findsNothing);
  });

  testWidgets('a locked Premium copy: no Start or Change days', (tester) async {
    final copy = program(id: 'p1', lengthWeeks: 8, premium: true);
    await pump(
      tester,
      ready(programs: [copy], activeProgram: active, premium: false),
    );

    expect(find.text('Start Lower'), findsNothing);
    expect(find.text('Change days'), findsNothing);
    expect(find.text('Stop'), findsOneWidget);
    expect(
      find.text(
        'This program came from Premium, which has ended. It carries '
        'on once you get Premium again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Weekly sets in this program'), findsOneWidget);
  });

  testWidgets('a locked program not running opens the paywall on Start', (
    tester,
  ) async {
    final copy = program(id: 'p1', lengthWeeks: 8, premium: true);
    await pump(tester, ready(programs: [copy], premium: false));

    await tester.tap(find.text('Start program'));
    await settle(tester);
    expect(paywalls, 1);
    verifyNever(() => detail.start(any()));
  });

  testWidgets('a day opens to its exercises and closes', (tester) async {
    await pump(tester, ready(activeProgram: active));

    // The next day is open while active.
    expect(find.text('3 × 8–12 · Rest 1:30'), findsNWidgets(2));
    await tester.tap(find.text('Day 2 · Lower'));
    await settle(tester);
    expect(find.text('3 × 8–12 · Rest 1:30'), findsNothing);
    await tester.tap(find.text('Day 1 · Upper'));
    await settle(tester);
    expect(find.text('3 × 8–12 · Rest 1:30'), findsNWidgets(2));
  });

  testWidgets('⋯ holds Edit, Duplicate and Delete; Delete asks', (
    tester,
  ) async {
    await pump(tester, ready(activeProgram: active));

    await tester.tap(options());
    await settle(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(
      find.text(
        'This is your active program. Deleting it also stops it. '
        "This can't be undone.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    verify(() => detail.delete()).called(1);
  });

  testWidgets('a program that is gone, and a list that failed', (tester) async {
    await pump(tester, ready(programs: const []));
    expect(find.text('This program no longer exists.'), findsOneWidget);

    await pump(
      tester,
      const ProgramListState(status: ProgramListStatus.failure),
    );
    expect(find.text("Couldn't load your programs."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('▶ on a day row goes through the premium gate when locked', (
    tester,
  ) async {
    final copy = program(id: 'p1', lengthWeeks: 8, premium: true);
    await pump(tester, ready(programs: [copy], premium: false));

    expect(find.bySemanticsLabel('Start this day'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Start this day').first);
    await settle(tester);
    // The status is unknown here, so the gate asks to wait.
    expect(
      find.text('Checking your subscription. Try again in a moment.'),
      findsOneWidget,
    );
    verifyNever(() => detail.start(any()));
  });
}
