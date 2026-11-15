import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/rest_timer_cubit.dart';
import 'package:get_workout/features/workout/presentation/widgets/progression_hint.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';
import 'package:get_workout/features/workout/presentation/workout_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';

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

  Future<void> pump(
    WidgetTester tester,
    ActiveWorkoutState state, {
    RestTimerState rest = const RestTimerState(),
    ({double kg, int reps})? progression,
    List<Program> programs = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ActiveWorkoutCubit>.value(value: cubit),
          BlocProvider<RestTimerCubit>.value(value: timer),
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<EquipmentCubit>.value(value: equipment),
          BlocProvider<ProgramListCubit>.value(value: programList),
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
}
