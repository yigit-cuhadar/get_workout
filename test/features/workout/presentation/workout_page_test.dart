import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_review/forge_review.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/rest_timer_cubit.dart';
import 'package:get_workout/features/workout/presentation/widgets/progression_hint.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';
import 'package:get_workout/features/workout/presentation/workout_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../app/review_prompt_stand_in.dart';
import '../fixtures.dart';
import '../../../fake_analytics.dart';

class _MockWorkout extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class _MockRestTimer extends MockCubit<RestTimerState>
    implements RestTimerCubit {}

class _MockSettings extends MockCubit<SettingsState> implements SettingsCubit {}

class _MockCatalogue extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _MockPrograms extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _MockEquipment extends MockCubit<EquipmentState>
    implements EquipmentCubit {}

class _MockBodyModel extends MockCubit<BodyModelState>
    implements BodyModelCubit {}

void main() {
  setUpAll(() => registerFallbackValue(0.0));

  late _MockWorkout cubit;
  late _MockRestTimer timer;

  final squat = exercise('Squat', [
    lift(100, 5),
    lift(100, 5, done: false),
  ]).copyWith(goal: () => item('Squat', sets: 2, repMin: 5, repMax: 8));

  ActiveWorkoutState active(
    List<WorkoutExercise> exercises, {
    bool waits = false,
    Rest? rest,
    SetRef? picked,
  }) => ActiveWorkoutState(
    status: WorkoutStatus.active,
    workout: Workout(
      id: 'w',
      startedAt: DateTime.now(),
      name: 'Legs',
      exercises: exercises,
    ),
    rest: rest,
    entryWaitsForRest: waits,
    picked: picked,
    weightUnit: WeightUnit.kg,
  );

  late MockReviews review;

  Future<void> pump(
    WidgetTester tester,
    ActiveWorkoutState state, {
    RestTimerState rest = const RestTimerState(),
    ({double kg, int reps})? progression,
    List<Program> programs = const [],
    ReviewHistory reviews = askedThisVersion,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(sl.reset);
    review = registerReviewPrompt(history: reviews);
    cubit = _MockWorkout();
    whenListen(
      cubit,
      const Stream<ActiveWorkoutState>.empty(),
      initialState: state,
    );
    when(() => cubit.canEdit).thenReturn(true);
    when(() => cubit.pageOpened()).thenReturn(null);
    when(() => cubit.progressionFor(any())).thenReturn(progression);
    when(() => cubit.applyProgression(any(), any())).thenReturn(null);
    when(() => cubit.roundRestS(any())).thenReturn(90);
    when(() => cubit.exerciseRestS(any())).thenReturn(90);
    when(() => cubit.warmupSettings).thenReturn(const WarmupSettings());
    timer = _MockRestTimer();
    whenListen(timer, const Stream<RestTimerState>.empty(), initialState: rest);
    final settings = _MockSettings();
    when(() => settings.state).thenReturn(
      const SettingsState(
        UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
        loaded: true,
      ),
    );
    final catalogue = _MockCatalogue();
    when(() => catalogue.state).thenReturn(const CatalogueReady([]));
    final programList = _MockPrograms();
    when(() => programList.state).thenReturn(
      ProgramListState(status: ProgramListStatus.ready, programs: programs),
    );
    final equipment = _MockEquipment();
    when(() => equipment.state).thenReturn(const EquipmentState(null));
    final body = _MockBodyModel();
    when(() => body.state).thenReturn(const BodyModelFailed());
    when(body.load).thenAnswer((_) async {});
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          RepositoryProvider.value(value: fakeAnalytics()),
          BlocProvider<ActiveWorkoutCubit>.value(value: cubit),
          BlocProvider<RestTimerCubit>.value(value: timer),
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<EquipmentCubit>.value(value: equipment),
          BlocProvider<ProgramListCubit>.value(value: programList),
          BlocProvider<BodyModelCubit>.value(value: body),
        ],
        child: MaterialApp(
          theme: AppPreset.shipped.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WorkoutPage(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the header names the selected set\'s exercise', (tester) async {
    await pump(tester, active([squat], picked: (exercise: 0, set: 1)));
    expect(find.text('Legs · exercise 1 of 1'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Log set'), findsOneWidget);
  });

  testWidgets('an empty workout says how to begin, without a panel', (
    tester,
  ) async {
    await pump(tester, active(const []));
    expect(find.text('Add exercises to start logging.'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('Log set'), findsNothing);
  });

  testWidgets('the rest a tick started takes the panel\'s place', (
    tester,
  ) async {
    await pump(
      tester,
      active(
        [squat],
        waits: true,
        rest: Rest(
          endsAt: DateTime.now().add(const Duration(seconds: 72)),
          after: (exercise: 0, set: 0),
        ),
      ),
      rest: const RestTimerState(
        phase: RestPhase.running,
        remainingS: 72,
        totalS: 90,
      ),
    );
    expect(find.byType(RestPanel), findsOneWidget);
    expect(find.text('next: set 2 · 100 × 5'), findsOneWidget);
    expect(find.text('Log set'), findsNothing);
  });

  testWidgets('a set picked while resting shows under the rest\'s line', (
    tester,
  ) async {
    await pump(
      tester,
      active([squat], picked: (exercise: 0, set: 1)),
      rest: const RestTimerState(
        phase: RestPhase.running,
        remainingS: 72,
        totalS: 90,
      ),
    );
    expect(find.byType(RestPanel), findsNothing);
    expect(find.text('Rest 1:12'), findsOneWidget);
    expect(find.text('Log set'), findsOneWidget);
  });

  testWidgets('every set done offers to finish', (tester) async {
    final done = squat.copyWith(sets: [lift(100, 5), lift(100, 5)]);
    await pump(tester, active([done]));
    expect(find.text('All sets done'), findsOneWidget);
    expect(find.text('Finish workout'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
  });

  testWidgets('the progression hint fills the load when tapped', (
    tester,
  ) async {
    await pump(
      tester,
      active([squat], picked: (exercise: 0, set: 1)),
      progression: (kg: 102.5, reps: 8),
    );
    expect(
      find.text('You hit 8 reps last time. Try 102.5 kg.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(ProgressionHint));
    verify(() => cubit.applyProgression(0, 102.5)).called(1);
  });

  testWidgets('a group says its rest after each round', (tester) async {
    await pump(
      tester,
      active([
        squat.copyWith(group: () => 'A'),
        exercise('Bench', [lift(80, 8, done: false)], group: 'A'),
      ]),
    );
    expect(find.text('Superset A · rest after each round 1:30'), findsWidgets);
  });

  testWidgets('the exercise menu lists its actions in the workout', (
    tester,
  ) async {
    await pump(tester, active([squat], picked: (exercise: 0, set: 1)));
    await tester.tap(find.bySemanticsLabel('Exercise options').first);
    await tester.pumpAndSettle();
    for (final label in [
      'Swap exercise',
      'Exercise details',
      'Add note',
      'Rest time · 1:30',
      'Warm-up sets',
      'Remove exercise',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Finish shows its loading state while finishing', (tester) async {
    final state = active([squat], picked: (exercise: 0, set: 1));
    await pump(
      tester,
      ActiveWorkoutState(
        status: WorkoutStatus.finishing,
        workout: state.workout,
        picked: state.picked,
      ),
    );
    final finish = tester.widget<ForgeButton>(
      find.widgetWithText(ForgeButton, 'Finish'),
    );
    expect(finish.loading, isTrue);
    expect(find.byType(Progress), findsOneWidget);
  });

  testWidgets('Swap leaves the menu once every set is done', (tester) async {
    final done = exercise('Squat', [lift(100, 5)]);
    await pump(tester, active([done, squat], picked: (exercise: 0, set: 0)));
    await tester.tap(find.bySemanticsLabel('Exercise options').first);
    await tester.pumpAndSettle();
    expect(find.text('Exercise details'), findsOneWidget);
    expect(find.text('Swap exercise'), findsNothing);
  });

  testWidgets('the workout note is a card whose Add opens the sheet', (
    tester,
  ) async {
    await pump(tester, active([squat], picked: (exercise: 0, set: 1)));
    when(() => cubit.setNote(any())).thenReturn(null);
    // The page's list, not a field's own scrollable.
    await tester.scrollUntilVisible(
      find.text('Workout note'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Tight shoulder');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => cubit.setNote('Tight shoulder')).called(1);
  });

  testWidgets('the open card\'s menu opens on one tap', (tester) async {
    final bench = exercise('Bench', [
      lift(60, 8, type: SetType.warmup, done: false),
      lift(80, 8, done: false),
    ]);
    await pump(tester, active([squat, bench], picked: (exercise: 1, set: 1)));
    final options = find.bySemanticsLabel('Exercise options');
    await tester.tap(options.last);
    await tester.pumpAndSettle();
    expect(find.text('Swap exercise'), findsOneWidget);
  });

  testWidgets('the open card\'s menu opens on one tap, on a warm-up too', (
    tester,
  ) async {
    final rdl = exercise('Romanian Deadlift', [
      lift(60, 8, type: SetType.warmup, done: false),
      lift(70, 8, type: SetType.warmup, done: false),
      lift(100, 8, done: false),
    ]).copyWith(goal: () => item('Romanian Deadlift', sets: 1));
    await pump(tester, active([rdl, squat], picked: (exercise: 0, set: 0)));
    await tester.tap(find.bySemanticsLabel('Exercise options').first);
    await tester.pumpAndSettle();
    expect(find.text('Swap exercise'), findsOneWidget);
  });

  testWidgets('a program day goes by its day name in the header', (
    tester,
  ) async {
    final state = active([squat], picked: (exercise: 0, set: 1));
    await pump(
      tester,
      ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: Workout(
          id: 'w',
          startedAt: DateTime.now(),
          programId: 'p1',
          dayIndex: 0,
          name: 'Upper/Lower 4-Day · Lower 1',
          exercises: state.workout!.exercises,
        ),
        picked: state.picked,
      ),
      programs: const [
        Program(
          id: 'p1',
          name: 'Upper/Lower 4-Day',
          days: [ProgramDay(name: 'Lower 1', items: [])],
        ),
      ],
    );
    expect(find.text('Lower 1 · exercise 1 of 1'), findsOneWidget);
  });

  testWidgets('a warm-up\'s line is in the body font, not the data font', (
    tester,
  ) async {
    final rdl = exercise('Romanian Deadlift', [
      lift(60, 8, type: SetType.warmup, done: false),
      lift(100, 8, done: false),
    ]);
    await pump(tester, active([rdl], picked: (exercise: 0, set: 0)));
    final line = tester.widget<Text>(
      find.text('A lighter set to get ready. Not counted in your stats.'),
    );
    expect(line.style!.fontFamily, isNot(contains('Mono')));
  });

  group('summary', () {
    final day = DateTime(2026, 11, 13, 18);
    ActiveWorkoutState finished({
      String? programId,
      WorkoutSummary summary = const WorkoutSummary(
        duration: Duration(minutes: 52),
        volumeKg: 12400,
        setCount: 18,
        exerciseCount: 6,
      ),
      List<ProgramItem>? dayChanges,
    }) => ActiveWorkoutState(
      status: WorkoutStatus.finished,
      workout: Workout(
        id: 'w',
        startedAt: day,
        finishedAt: day.add(const Duration(minutes: 52)),
        programId: programId,
        dayIndex: programId == null ? null : 0,
        name: 'Push',
        exercises: [squat],
      ),
      summary: summary,
      dayChanges: dayChanges,
    );
    const program = Program(
      id: 'p',
      name: 'Push Pull Legs',
      days: [ProgramDay(name: 'Push', items: [])],
    );

    testWidgets('a free workout offers Save as program; Done closes it', (
      tester,
    ) async {
      await pump(tester, finished());
      expect(find.text('Workout done · Fri, Nov 13'), findsOneWidget);
      expect(find.text('Save as program'), findsOneWidget);
      when(() => cubit.summaryShown()).thenReturn(null);
      await tester.tap(find.text('Done'));
      verify(() => cubit.summaryShown()).called(1);
    });

    testWidgets('the second workout asks for a review; Yes! opens the '
        'store\'s prompt', (tester) async {
      await pump(
        tester,
        finished(),
        reviews: const ReviewHistory(events: 1, lastEventId: 'v'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enjoying GetWorkout?'), findsOneWidget);
      await tester.tap(find.text('Yes!'));
      await tester.pumpAndSettle();
      expect(find.text('Enjoying GetWorkout?'), findsNothing);
      verify(review.requestReview).called(1);
    });

    testWidgets('Not really thanks in the same dialog; Close leaves the '
        'summary', (tester) async {
      await pump(
        tester,
        finished(),
        reviews: const ReviewHistory(events: 1, lastEventId: 'v'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not really'));
      await tester.pumpAndSettle();
      expect(find.text('Thanks for telling us'), findsOneWidget);
      expect(find.text('Write to us'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Thanks for telling us'), findsNothing);
      expect(find.text('Save as program'), findsOneWidget);
      verifyNever(review.requestReview);
    });

    testWidgets('the first workout ever, with its paywall, counts without '
        'asking', (tester) async {
      await pump(
        tester,
        finished(
          summary: const WorkoutSummary(
            duration: Duration(minutes: 52),
            volumeKg: 12400,
            setCount: 18,
            exerciseCount: 6,
            firstEver: true,
          ),
        ),
        reviews: const ReviewHistory(events: 1, lastEventId: 'v'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enjoying GetWorkout?'), findsNothing);
      verify(
        () => review.save(const ReviewHistory(events: 2, lastEventId: 'w')),
      ).called(1);
    });

    testWidgets('compares with the day\'s last workout', (tester) async {
      await pump(
        tester,
        finished(
          programId: 'p',
          summary: WorkoutSummary(
            duration: const Duration(minutes: 52),
            volumeKg: 12400,
            setCount: 18,
            exerciseCount: 6,
            programWeek: 3,
            previous: (
              startedAt: DateTime(2026, 11, 6, 18),
              duration: const Duration(minutes: 56),
              volumeKg: 11700,
              setCount: 18,
            ),
            muscleSets: const {Muscle.pec: 10, Muscle.triceps: 6},
          ),
        ),
        programs: const [program],
      );
      expect(find.text('Push Pull Legs · week 3'), findsOneWidget);
      // Each change with the day it compares with, under its number.
      expect(find.text('−4 min vs Fri, Nov 6'), findsOneWidget);
      expect(find.text('+6 % vs Fri, Nov 6'), findsOneWidget);
      expect(find.text('same as Fri, Nov 6'), findsOneWidget);
      expect(find.text('Chest 10 sets · Triceps 6'), findsOneWidget);
      expect(find.text('Save as program'), findsNothing);
    });

    testWidgets('an hour or more reads in hours, records name their '
        'exercises; no change without a last workout', (tester) async {
      await pump(
        tester,
        finished(
          summary: const WorkoutSummary(
            duration: Duration(minutes: 72),
            volumeKg: 12400,
            setCount: 18,
            exerciseCount: 6,
            records: [
              SummaryRecord(
                exerciseId: 'leg_press',
                name: 'Leg Press',
                set: WorkoutSet(weightKg: 140, reps: 8),
                loggingType: LoggingType.weightReps,
                kinds: [RecordKind.heaviestWeight],
                gain: (kind: RecordKind.heaviestWeight, amount: 5),
              ),
            ],
          ),
        ),
      );
      expect(find.text('1 h 12 min'), findsOneWidget);
      expect(find.text('Leg Press'), findsWidgets);
      expect(find.textContaining(' vs '), findsNothing);
    });

    testWidgets('a changed program day asks before saving the changes', (
      tester,
    ) async {
      await pump(
        tester,
        finished(programId: 'p', dayChanges: const []),
        programs: const [program],
      );
      when(() => cubit.updateProgramDay()).thenAnswer((_) async {});
      await tester.tap(find.text('Save changes to Push'));
      await tester.pumpAndSettle();
      expect(find.text('Update Push?'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      verify(() => cubit.updateProgramDay()).called(1);
    });

    testWidgets('no record says how close the best came', (tester) async {
      await pump(
        tester,
        finished(
          summary: const WorkoutSummary(
            duration: Duration(minutes: 52),
            volumeKg: 12400,
            setCount: 18,
            exerciseCount: 6,
            closest: (name: 'Bench Press', kg: 2.5),
          ),
        ),
      );
      expect(
        find.text(
          'No new records this time. Bench Press was 2.5 kg off your best.',
        ),
        findsOneWidget,
      );
    });
  });
}
