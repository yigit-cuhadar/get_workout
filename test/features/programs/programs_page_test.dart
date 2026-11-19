import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/featured_card.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
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
  // Wednesday 11 November 2026, in a week from Monday 9.
  final today = CalendarDate(2026, 11, 11);
  final upperLower = program(id: 'p1', lengthWeeks: 8);
  final arms = program(id: 'p2', name: 'Arms');
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 4],
    nextDayIndex: 1,
    nextDate: CalendarDate(2026, 11, 12),
    startedAt: DateTime(2026, 11, 2),
  );

  late _ListCubit list;
  late _DetailCubit detail;
  late int paywalls;

  ProgramListState ready({
    List<Program>? programs,
    ActiveProgram? activeProgram,
    List<PlannedDay> weekPlan = const [],
    bool finished = false,
    int? workoutCount,
    PlannedDay? missed,
    bool? premium = true,
  }) => ProgramListState(
    status: ProgramListStatus.ready,
    programs: programs ?? [arms, upperLower],
    active: activeProgram,
    weekPlan: weekPlan,
    finished: finished,
    workoutCount: workoutCount,
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
    when(() => detail.start(any())).thenAnswer((_) async {});
    when(() => detail.duplicate(any())).thenAnswer((_) async {});
    when(list.refreshNow).thenReturn(null);
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
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final entitlement = _EntitlementCubit();
    when(() => entitlement.state).thenReturn(const EntitlementUnknown());
    Widget location(BuildContext _, GoRouterState state) =>
        Text('at ${state.uri.path}');
    final router = GoRouter(
      initialLocation: '/programs',
      routes: [
        GoRoute(path: '/programs', builder: (_, _) => const ProgramsPage()),
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

  testWidgets('the active program\'s band: its week and days, no Start', (
    tester,
  ) async {
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

    // The week over a bar with a part per week, this one filled by its
    // days done.
    expect(find.text('Active program'), findsOneWidget);
    expect(find.text('Week 2 of 8'), findsOneWidget);
    expect(find.text('1 of 2 days this week'), findsOneWidget);
    final bar = tester.widget<Progress>(find.byType(Progress));
    expect(bar.segments, 8);
    expect(bar.value, closeTo((1 + 1 / 2) / 8, 1e-9));
    // Today starts the day; Programs shows the plan.
    expect(find.text('Start Lower'), findsNothing);
    expect(find.text('Start empty workout'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    // The program page holds the weekly sets.
    expect(find.text('Weekly sets in this program'), findsNothing);
    expect(find.text('Other programs'), findsOneWidget);
    expect(find.text('Arms'), findsOneWidget);
  });

  testWidgets('a tap on the band opens the program, with no chevron', (
    tester,
  ) async {
    await pump(tester, ready(activeProgram: active));

    final band = find.byType(FeaturedCard);
    expect(
      find.descendant(
        of: band,
        matching: find.byWidgetPredicate(
          (w) => w is ForgeIcon && w.icon == ForgeIcons.chevronRight,
        ),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Week 2 of 8'));
    await settle(tester);
    expect(find.text('at /programs/p1'), findsOneWidget);
  });

  testWidgets('a missed day is its row alone; Today asks about it', (
    tester,
  ) async {
    final missed = PlannedDay(
      date: CalendarDate(2026, 11, 9),
      dayIndex: 1,
      status: PlannedStatus.missed,
    );
    await pump(
      tester,
      ready(activeProgram: active, weekPlan: [missed], missed: missed),
    );

    expect(find.text('Start Lower'), findsNothing);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Do it today'), findsNothing);
    expect(find.text('Move to Monday'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('⋯ › Stop program asks first, then stops', (tester) async {
    await pump(tester, ready(activeProgram: active));

    await tester.tap(find.bySemanticsLabel('Program options'));
    await settle(tester);
    expect(find.text('Open program'), findsOneWidget);
    expect(find.text('Change days'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);

    await tester.tap(find.text('Stop program'));
    await settle(tester);
    expect(find.text('Stop this program?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    verifyNever(() => detail.stop());

    await tester.tap(find.bySemanticsLabel('Program options'));
    await settle(tester);
    await tester.tap(find.text('Stop program'));
    await settle(tester);
    await tester.tap(find.text('Stop program').last);
    await settle(tester);
    verify(() => detail.stop()).called(1);
  });

  testWidgets('a failed stop says so', (tester) async {
    whenListen(
      detail,
      Stream.fromIterable(const [
        ProgramDetailState(status: ProgramDetailStatus.working),
        ProgramDetailState(
          status: ProgramDetailStatus.failed,
          failure: UnknownFailure('refused'),
          action: ProgramDetailAction.stop,
        ),
      ]),
      initialState: const ProgramDetailState(),
    );
    await pump(tester, ready(activeProgram: active));
    await tester.pump();

    expect(find.text("Couldn't stop the program. Try again."), findsOneWidget);
  });

  testWidgets('⋯ › Duplicate opens the copy', (tester) async {
    whenListen(
      detail,
      Stream.fromIterable(const [
        ProgramDetailState(
          status: ProgramDetailStatus.duplicated,
          copyId: 'p3',
        ),
      ]),
      initialState: const ProgramDetailState(),
    );
    await pump(tester, ready(activeProgram: active));
    await settle(tester);

    expect(find.text('at /programs/p3'), findsOneWidget);
  });

  testWidgets('a finished program counts its workouts and runs again', (
    tester,
  ) async {
    await pump(
      tester,
      ready(activeProgram: active, finished: true, workoutCount: 24),
    );

    expect(find.text('Finished · 8 of 8 weeks'), findsOneWidget);
    expect(find.text('24 workouts'), findsOneWidget);
    expect(find.text('New program'), findsNWidgets(2));
    expect(find.text('Weekly sets in this program'), findsNothing);

    await tester.tap(find.text('Run it again'));
    await settle(tester);
    expect(find.text('Pick 2 training days'), findsOneWidget);
    await tester.tap(find.text('Start program'));
    await settle(tester);
    verify(() => detail.start(const [1, 4])).called(1);
  });

  testWidgets('a locked Premium copy keeps its band with the notice', (
    tester,
  ) async {
    final copy = program(id: 'p1', lengthWeeks: 8, premium: true);
    await pump(
      tester,
      ready(programs: [arms, copy], activeProgram: active, premium: false),
    );

    expect(find.text('Week 2 of 8'), findsOneWidget);
    expect(find.text('Premium has ended'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Program options'));
    await settle(tester);
    expect(find.text('Open program'), findsOneWidget);
    expect(find.text('Change days'), findsNothing);
    await tester.tapAt(Offset.zero);
    await settle(tester);
    await tester.tap(find.text('See Premium'));
    expect(paywalls, 1);
  });

  testWidgets(
    'without an active program the prompt has no action; the row leads to the catalogue',
    (tester) async {
      await pump(tester, ready());

      expect(find.text('No active program'), findsOneWidget);
      expect(find.text('Your programs'), findsOneWidget);
      expect(find.text('See ready-made programs'), findsNothing);
      await tester.tap(find.text('Ready-made programs'));
      await settle(tester);
      expect(find.text('at /programs/catalogue'), findsOneWidget);
    },
  );

  testWidgets('without any program it says so', (tester) async {
    await pump(tester, ready(programs: const []));

    expect(find.text('No programs yet'), findsOneWidget);
    expect(find.text('Your programs'), findsNothing);
  });

  testWidgets('a failed load offers Retry', (tester) async {
    when(list.retry).thenReturn(null);
    await pump(
      tester,
      const ProgramListState(status: ProgramListStatus.failure),
    );

    expect(find.text("Couldn't load your programs."), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(list.retry).called(1);
  });
}
