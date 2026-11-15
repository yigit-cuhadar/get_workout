import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/sparkline.dart' as app;
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_week.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/progress/domain/body_snapshot.dart';
import 'package:get_workout/features/progress/domain/measurement_prompt.dart';
import 'package:get_workout/features/progress/domain/progress_usecases.dart';
import 'package:get_workout/features/progress/presentation/measurement_prompt_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_page.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class _BodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

class _BodyCubit extends MockCubit<ProgressBodyState>
    implements ProgressBodyCubit {}

class _PromptCubit extends MockCubit<MeasurementPrompt?>
    implements MeasurementPromptCubit {}

class _WeekCubit extends MockCubit<TodayWeekState> implements TodayWeekCubit {}

class _VolumeCubit extends MockCubit<TodayVolumeState>
    implements TodayVolumeCubit {}

class _StrengthCubit extends MockCubit<ProgressStrengthState>
    implements ProgressStrengthCubit {}

class _CardioCubit extends MockCubit<CardioListState>
    implements CardioListCubit {}

class _StepsCubit extends MockCubit<TodayStepsState>
    implements TodayStepsCubit {}

class _ProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

void main() {
  // Friday 13 November 2026, in a week from Monday 9.
  final friday = CalendarDate(2026, 11, 13);
  final monday = CalendarDate(2026, 11, 9);
  final days = [for (var i = 0; i < 7; i++) monday.addDays(i)];
  final bench = move('bench', name: 'Bench Press');
  final weighed = ProgressBodyState(
    status: BodyListStatus.ready,
    snapshot: BodySnapshot(
      latest: (date: DateTime(2026, 11, 13), kg: 82.4),
      previous: (date: DateTime(2026, 11, 8), kg: 82.8),
      weights: [
        (date: DateTime(2026, 11, 8), kg: 82.8),
        (date: DateTime(2026, 11, 13), kg: 82.4),
      ],
      latestBodyFat: (date: DateTime(2026, 11, 1), percent: 19.5),
    ),
  );
  WeekVolume volumeOf(int sets) => WeekVolume(monday, [
    VolumeEntry(
      workoutId: 'w1',
      workoutName: 'Push',
      startedAt: DateTime(2026, 11, 9, 18),
      exerciseId: 'bench',
      exerciseName: 'Bench Press',
      sets: sets,
      muscles: (main: const [Muscle.pec], secondary: const []),
    ),
  ]);
  final run = CardioSession(
    type: CardioType.values.first,
    date: DateTime(2026, 11, 10, 7),
    duration: const Duration(minutes: 74),
    distanceKm: 23.6,
  );

  late _BodyCubit body;
  late _PromptCubit prompt;
  late _VolumeCubit volume;
  late _StrengthCubit strength;
  late _CardioCubit cardio;
  late _StepsCubit steps;
  late _ProgramListCubit programs;

  setUp(() {
    final bodyList = _BodyListCubit();
    when(() => bodyList.state).thenReturn(const BodyListState());
    body = _BodyCubit();
    when(() => body.state).thenReturn(weighed);
    prompt = _PromptCubit();
    when(() => prompt.state).thenReturn(null);
    when(prompt.dismiss).thenAnswer((_) async {});
    final week = _WeekCubit();
    when(() => week.state).thenReturn(
      TodayWeekState(today: friday, days: days, status: TodayWeekStatus.ready),
    );
    volume = _VolumeCubit();
    when(() => volume.state).thenReturn(
      TodayVolumeState(
        weekStart: monday,
        status: TodayVolumeStatus.ready,
        week: volumeOf(12),
      ),
    );
    strength = _StrengthCubit();
    when(() => strength.state).thenReturn(
      ProgressStrengthState(
        status: ProgressStrengthStatus.ready,
        highlight: const StrengthHighlight(
          exerciseId: 'bench',
          e1rmKg: 104,
          change: (kg: 3, weeks: 8),
        ),
        exercise: bench,
        trained: true,
      ),
    );
    cardio = _CardioCubit();
    when(() => cardio.firstWeekday).thenReturn(DateTime.monday);
    when(() => cardio.state).thenReturn(
      CardioListState(
        status: CardioListStatus.ready,
        sessions: [run],
        chart: [
          CardioWeek(DateTime(2026, 11, 9), [run, run]),
        ],
      ),
    );
    steps = _StepsCubit();
    when(() => steps.state).thenReturn(
      const TodayStepsState(
        status: TodayStepsStatus.ready,
        progress: StepGoalProgress(steps: 6240, goal: 10000),
      ),
    );
    when(() => steps.load(any())).thenAnswer((_) async {});
    programs = _ProgramListCubit();
    when(() => programs.state)
        .thenReturn(const ProgramListState(status: ProgramListStatus.ready));
    when(programs.refreshNow).thenReturn(null);
    sl
      ..registerSingleton<BodyListCubit>(bodyList)
      ..registerSingleton<CardioListCubit>(cardio)
      ..registerSingleton<ProgramListCubit>(programs)
      ..registerFactory<ProgressBodyCubit>(() => body)
      ..registerFactory<MeasurementPromptCubit>(() => prompt)
      ..registerFactoryParam<TodayWeekCubit, int, void>((_, _) => week)
      ..registerFactoryParam<TodayVolumeCubit, int, void>((_, _) => volume)
      ..registerFactory<ProgressStrengthCubit>(() => strength)
      ..registerFactory<TodayStepsCubit>(() => steps);
  });

  tearDown(sl.reset);

  /// Progress at its route, every other route showing its location.
  Future<void> pumpProgress(WidgetTester tester) async {
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
      initialLocation: '/progress',
      routes: [
        GoRoute(path: '/progress', builder: (_, _) => const ProgressPage()),
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

  testWidgets('every area as its card, as the board draws them', (
    tester,
  ) async {
    await pumpProgress(tester);

    expect(find.text('82.4 kg'), findsOneWidget);
    expect(find.text('−0.4 since Nov 8'), findsOneWidget);
    expect(
      tester.widgetList<ForgeIcon>(find.byType(ForgeIcon)).map((i) => i.icon),
      contains(ForgeIcons.trendingDown),
    );
    expect(find.text('19.5 % fat'), findsOneWidget);
    expect(find.byType(app.Sparkline), findsOneWidget);
    expect(find.text('Nov 9–15'), findsOneWidget);
    expect(find.text('12 sets'), findsOneWidget);
    expect(find.text('Bench Press e1RM'), findsOneWidget);
    expect(find.text('104 kg'), findsOneWidget);
    expect(find.text('+3 in 8 weeks'), findsOneWidget);
    expect(find.text('this week'), findsOneWidget);
    expect(find.text('2 sessions · 47.2 km · 148 min'), findsOneWidget);
    expect(find.text('6,240 / 10,000'), findsOneWidget);
    expect(find.byType(TipBanner), findsNothing);

    await tester.tap(find.text('82.4 kg'));
    await tester.pumpAndSettle();
    expect(find.text('at /progress/body'), findsOneWidget);
  });

  testWidgets('weekly volume against the active program\'s week', (
    tester,
  ) async {
    when(() => programs.state).thenReturn(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
        active: ActiveProgram(
          programId: 'p1',
          weekdays: const [1, 5],
          nextDayIndex: 0,
          nextDate: friday,
          startedAt: DateTime(2026, 11, 2),
        ),
      ),
    );
    when(() => volume.state).thenReturn(
      TodayVolumeState(
        weekStart: monday,
        status: TodayVolumeStatus.ready,
        week: volumeOf(6),
      ),
    );
    await pumpProgress(tester);

    expect(find.text('6 / 12 sets'), findsOneWidget);
    expect(find.byType(Progress), findsNWidgets(2));
  });

  testWidgets('one weigh-in shows the box where the line will be', (
    tester,
  ) async {
    when(() => body.state).thenReturn(
      ProgressBodyState(
        status: BodyListStatus.ready,
        snapshot: BodySnapshot(
          latest: (date: DateTime(2026, 11, 13), kg: 82.4),
          weights: [(date: DateTime(2026, 11, 13), kg: 82.4)],
        ),
      ),
    );
    await pumpProgress(tester);

    expect(find.text('Log again to see the trend'), findsOneWidget);
    expect(find.textContaining('since'), findsNothing);
  });

  testWidgets('a body list that failed keeps the buttons and retries', (
    tester,
  ) async {
    when(() => body.state)
        .thenReturn(const ProgressBodyState(status: BodyListStatus.failure));
    when(body.retry).thenReturn(null);
    await pumpProgress(tester);

    expect(find.text('Couldn\'t load your entries'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(body.retry).called(1);
  });

  testWidgets('new user: each card says when it fills', (tester) async {
    when(() => body.state)
        .thenReturn(const ProgressBodyState(status: BodyListStatus.ready));
    when(() => volume.state).thenReturn(
      TodayVolumeState(
        weekStart: monday,
        status: TodayVolumeStatus.ready,
        week: WeekVolume(monday, const []),
      ),
    );
    when(() => strength.state).thenReturn(
      const ProgressStrengthState(status: ProgressStrengthStatus.ready),
    );
    when(() => cardio.state)
        .thenReturn(const CardioListState(status: CardioListStatus.ready));
    when(() => steps.state)
        .thenReturn(const TodayStepsState(status: TodayStepsStatus.setUp));
    await pumpProgress(tester);

    expect(find.text('No weigh-ins yet'), findsOneWidget);
    expect(find.text('Log your weight to start the trend'), findsOneWidget);
    expect(find.text('No sets this week.'), findsOneWidget);
    expect(find.text('Finish a workout to see your e1RM.'), findsOneWidget);
    expect(find.text('Log a session or connect a health app.'), findsOneWidget);
    expect(find.text('See your steps'), findsOneWidget);
  });

  testWidgets('a drop in danger; trained without an e1RM says how', (
    tester,
  ) async {
    when(() => strength.state).thenReturn(
      ProgressStrengthState(
        status: ProgressStrengthStatus.ready,
        highlight: const StrengthHighlight(
          exerciseId: 'bench',
          e1rmKg: 100,
          change: (kg: -1, weeks: 8),
        ),
        exercise: bench,
        trained: true,
      ),
    );
    await pumpProgress(tester);
    final drop = tester.widget<Text>(find.text('−1 in 8 weeks'));
    expect(
      drop.style?.color,
      ForgeStyle.of(tester.element(find.byType(ProgressPage))).colors.danger,
    );

    when(() => strength.state).thenReturn(
      const ProgressStrengthState(
        status: ProgressStrengthStatus.ready,
        trained: true,
      ),
    );
    await pumpProgress(tester);
    expect(
      find.text('Log a set with weight and reps to see your e1RM.'),
      findsOneWidget,
    );
  });

  testWidgets('no sessions this week, though some before', (tester) async {
    when(() => cardio.state).thenReturn(
      CardioListState(
        status: CardioListStatus.ready,
        sessions: [run],
        chart: [CardioWeek(DateTime(2026, 11, 9), const [])],
      ),
    );
    await pumpProgress(tester);
    expect(find.text('No sessions this week.'), findsOneWidget);
  });

  testWidgets('no steps card without a health store', (tester) async {
    when(
      () => steps.state,
    ).thenReturn(const TodayStepsState(status: TodayStepsStatus.unavailable));
    await pumpProgress(tester);
    expect(find.text('Steps'), findsNothing);
  });

  testWidgets('the measurement prompt starts the day, and swipes away', (
    tester,
  ) async {
    when(() => prompt.state).thenReturn(
      MeasurementPrompt(
        date: CalendarDate(2026, 11, 15),
        today: false,
        lastPhotos: (date: DateTime(2026, 11, 1), poses: PhotoPose.values),
      ),
    );
    await pumpProgress(tester);

    expect(find.text('Measurement day on Sunday'), findsOneWidget);
    expect(
      find.text('Last photos Sun, Nov 1 · Front, Right side, Left side, Back'),
      findsOneWidget,
    );
    await tester.drag(find.byType(TipBanner), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    verify(prompt.dismiss).called(1);
  });

  testWidgets('on the day itself, with no photos yet', (tester) async {
    when(() => prompt.state).thenReturn(
      MeasurementPrompt(date: CalendarDate(2026, 11, 15), today: true),
    );
    await pumpProgress(tester);
    expect(find.text('Measurement day today'), findsOneWidget);
    expect(find.text('No progress photos yet'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('at /progress/body/measure'), findsOneWidget);
  });
}
