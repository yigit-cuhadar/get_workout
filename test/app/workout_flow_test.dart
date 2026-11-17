import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/presentation/widgets/effort_question.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';
import 'package:get_workout/features/workout/presentation/workout_page.dart';

import '../features/programs/fixtures.dart';
import 'training_world.dart';

void main() {
  final upperLower = Program(
    id: 'p1',
    name: 'Upper Lower',
    days: [
      ProgramDay(name: 'Upper', items: [item('bench', sets: 1)]),
      ProgramDay(
        name: 'Lower',
        items: [item('squat', sets: 2, repMin: 5, repMax: 5)],
      ),
    ],
  );
  final exercises = [
    move('squat', name: 'Back Squat'),
    move('bench', name: 'Bench Press'),
  ];

  /// Lower is due today, a Wednesday.
  TrainingWorld world({bool restTimer = true}) {
    final world = TrainingWorld(
      exercises: exercises,
      settings: UserSettings(
        weightUnit: WeightUnit.kg,
        lengthUnit: LengthUnit.cm,
        restTimer: RestTimerSettings(enabled: restTimer, notify: false),
        warmups: const WarmupSettings(scheme: WarmupScheme.off),
        seenTips: Tip.values.toSet(),
      ),
    );
    world.programs
      ..add(upperLower)
      ..active = ActiveProgram(
        programId: 'p1',
        weekdays: const [1, 3],
        nextDayIndex: 1,
        nextDate: dateOf(flowStart),
        startedAt: DateTime(2026, 11, 2),
      );
    return world;
  }

  /// Types [value] into the set panel's field whose unit is [unit], as a
  /// tap on its value opens it for typing.
  Future<void> enterValue(
    WidgetTester tester,
    String unit,
    String value,
  ) async {
    final field = find.widgetWithText(StepperField, unit);
    await tester.tap(find.descendant(of: field, matching: find.text(unit)));
    await tester.pump();
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      value,
    );
    await tester.pump();
  }

  /// Skips the effort question a ticked working set asks; its Skip comes
  /// after the rest line's.
  Future<void> skipEffort(WidgetTester tester) => tapOn(
    tester,
    find
        .descendant(
          of: find.byType(EffortQuestion),
          matching: find.text('Skip'),
        )
        .last,
  );

  testWidgets('today\'s day is logged with a rest, finished and shown done', (
    tester,
  ) async {
    final app = world();
    await app.start(tester);

    await tapText(tester, 'Start Lower');
    expect(find.byType(WorkoutPage), findsOneWidget);
    expect(find.text('Back Squat'), findsWidgets);

    await enterValue(tester, 'kg', '100');
    await enterValue(tester, 'reps', '5');
    await tapText(tester, 'Log set');
    // The effort question comes first; the rest runs under it.
    await skipEffort(tester);
    expect(find.byType(RestPanel), findsOneWidget);

    app.now = flowStart.add(const Duration(minutes: 40));
    await tapText(tester, 'Finish');
    expect(find.text('Finish workout?'), findsOneWidget);
    await tapOn(tester, inDialog('Finish'));

    expect(find.text('Workout done · Wed, Nov 11'), findsOneWidget);
    final stored = app.workouts.workouts.values.single;
    expect(stored.exercises.single.sets.single.weightKg, 100);
    expect(stored.exercises.single.sets.single.reps, 5);

    await tapText(tester, 'Done');
    expect(find.byType(WorkoutPage), findsNothing);
    expect(find.text('Done today · Lower'), findsOneWidget);
    expect(find.text('Next: Upper'), findsOneWidget);
    expect(app.programs.active!.nextDayIndex, 0);

    await app.stop(tester);
  });

  testWidgets('with the rest timer off a tick goes on to the next set', (
    tester,
  ) async {
    final app = world(restTimer: false);
    await app.start(tester);

    await tapText(tester, 'Start Lower');
    await enterValue(tester, 'kg', '100');
    await enterValue(tester, 'reps', '5');
    await tapText(tester, 'Log set');
    await skipEffort(tester);

    expect(find.byType(RestPanel), findsNothing);
    expect(find.text('Log set'), findsOneWidget);

    await app.stop(tester);
  });

  testWidgets('an exercise is added from the picker', (tester) async {
    final app = world();
    await app.start(tester);
    await tapText(tester, 'Start Lower');

    await tapOn(tester, find.widgetWithText(ForgeAddButton, 'Add exercises'));
    await tapText(tester, 'Bench Press');
    await tapText(tester, 'Add 1 exercise');

    expect(find.byType(WorkoutPage), findsOneWidget);
    expect(find.text('Bench Press'), findsWidgets);
    expect(app.local.kept.draft!.exercises.map((e) => e.exerciseId), [
      'squat',
      'bench',
    ]);

    await app.stop(tester);
  });

  testWidgets('a discarded workout leaves the day to do', (tester) async {
    final app = world();
    await app.start(tester);
    await tapText(tester, 'Start Lower');
    await enterValue(tester, 'kg', '100');
    await enterValue(tester, 'reps', '5');
    await tapText(tester, 'Log set');
    await skipEffort(tester);

    await tapOn(tester, find.bySemanticsLabel('Workout options'));
    await tapText(tester, 'Discard workout');
    expect(find.text('Discard this workout?'), findsOneWidget);
    await tapOn(tester, inDialog('Discard'));

    expect(find.byType(WorkoutPage), findsNothing);
    expect(find.text('Start Lower'), findsOneWidget);
    expect(app.workouts.workouts, isEmpty);
    expect(app.local.kept.draft, isNull);

    await app.stop(tester);
  });

  testWidgets('an empty workout from Programs is filled, logged and saved', (
    tester,
  ) async {
    final app = world();
    await app.start(tester);
    await openTab(tester, 'Programs');

    await tapText(tester, 'Start empty workout');
    expect(find.text('Add exercises to start logging.'), findsOneWidget);
    await tapOn(tester, find.widgetWithText(ForgeButton, 'Add exercises'));
    await tapText(tester, 'Bench Press');
    await tapText(tester, 'Add 1 exercise');
    await enterValue(tester, 'kg', '60');
    await enterValue(tester, 'reps', '8');
    await tapText(tester, 'Log set');
    await skipEffort(tester);
    await tapText(tester, 'Finish');

    // Every set done: nothing to confirm.
    expect(find.text('Save as program'), findsOneWidget);
    final stored = app.workouts.workouts.values.single;
    expect(stored.programId, isNull);
    expect(stored.exercises.single.exerciseId, 'bench');
    // A free workout leaves the program where it was.
    expect(app.programs.active!.nextDayIndex, 1);

    await tapText(tester, 'Done');
    expect(find.text('Start empty workout'), findsOneWidget);

    await app.stop(tester);
  });
}
