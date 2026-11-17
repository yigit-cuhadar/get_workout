import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_builder_page.dart';
import 'package:get_workout/features/programs/presentation/program_detail_page.dart';

import '../features/programs/fixtures.dart';
import 'training_world.dart';

void main() {
  final exercises = [
    move('squat', name: 'Back Squat'),
    move('bench', name: 'Bench Press'),
    move('row', name: 'Barbell Row'),
  ];
  final upperLower = Program(
    id: 'p1',
    name: 'Upper Lower',
    days: [
      ProgramDay(name: 'Upper', items: [item('bench'), item('row')]),
      ProgramDay(name: 'Lower', items: [item('squat')]),
    ],
  );
  final wednesday = dateOf(flowStart);
  final monday = wednesday.addDays(-2);

  group('a ready-made program', () {
    TrainingWorld world() {
      final world = TrainingWorld(exercises: exercises);
      world.catalogue
        ..cards.add(card('c1', daysPerWeek: 2))
        ..days['c1'] = [
          ProgramDay(name: 'Push', items: [item('bench')]),
          ProgramDay(name: 'Pull', items: [item('row')]),
        ];
      return world;
    }

    testWidgets('is copied, started on the days picked and stopped', (
      tester,
    ) async {
      final app = world();
      await app.start(tester);
      expect(find.text('Pick your first program'), findsOneWidget);

      await openTab(tester, 'Programs');
      await tapText(tester, 'Ready-made programs');
      await tapText(tester, 'Program c1');
      await tapText(tester, 'Start this program');
      expect(find.text('Pick 2 training days'), findsOneWidget);
      // Monday and Thursday are offered; Wednesday is today.
      await tapOn(tester, inDialog('Thu'));
      await tapOn(tester, inDialog('Wed'));
      await tapOn(tester, inDialog('Start program'));

      final copy = app.programs.programs.values.single;
      expect(copy.name, 'Program c1');
      expect(copy.sourceId, 'c1');
      expect(app.programs.active, isNotNull);
      expect(app.programs.active!.programId, copy.id);
      expect(app.programs.active!.weekdays, [1, 3]);
      expect(app.programs.active!.nextDate, wednesday);
      expect(find.byType(ProgramDetailPage), findsOneWidget);
      expect(find.text('Next: Push'), findsOneWidget);

      await openTab(tester, 'Programs');
      await openTab(tester, 'Programs');
      expect(find.text('Program c1'), findsOneWidget);
      expect(find.text('Start Push'), findsOneWidget);

      await openTab(tester, 'Today');
      expect(find.text('Program c1'), findsOneWidget);
      expect(find.text('Start Push'), findsOneWidget);

      await openTab(tester, 'Programs');
      await tapOn(tester, find.byTooltip('Program options'));
      await tapText(tester, 'Stop program');
      expect(find.text('Stop this program?'), findsOneWidget);
      await tapOn(tester, inDialog('Stop program'));

      expect(app.programs.active, isNull);
      expect(find.text('No active program'), findsOneWidget);
      await openTab(tester, 'Today');
      expect(find.text('Pick your first program'), findsOneWidget);

      await app.stop(tester);
    });
  });

  group('a missed day', () {
    /// Upper was due Monday and is not done; today is Wednesday.
    TrainingWorld world() {
      final world = TrainingWorld(exercises: exercises);
      world.programs
        ..add(upperLower)
        ..active = ActiveProgram(
          programId: 'p1',
          weekdays: const [1, 3],
          nextDayIndex: 0,
          nextDate: monday,
          startedAt: DateTime(2026, 11, 2),
        );
      return world;
    }

    ActiveProgram active(TrainingWorld world) => world.programs.active!;

    testWidgets('is done today from Today', (tester) async {
      final app = world();
      await app.start(tester);
      expect(find.text('You missed Upper on Mon, Nov 9'), findsOneWidget);
      expect(find.text('Start Upper'), findsNothing);

      await tapText(tester, 'Do it today');

      expect(active(app).nextDayIndex, 0);
      expect(active(app).nextDate, wednesday);
      expect(find.text('Do it today'), findsNothing);
      expect(find.text('Start Upper'), findsOneWidget);
      await openTab(tester, 'Programs');
      expect(find.text('Start Upper'), findsOneWidget);

      await app.stop(tester);
    });

    testWidgets('moves to the next training day from Programs', (tester) async {
      final app = world();
      await app.start(tester);
      await openTab(tester, 'Programs');

      await tapText(tester, 'Move to Monday');

      expect(active(app).nextDayIndex, 0);
      expect(active(app).nextDate, CalendarDate(2026, 11, 16));
      expect(find.text('Do it today'), findsNothing);
      await openTab(tester, 'Today');
      expect(find.textContaining('You missed'), findsNothing);
      expect(find.textContaining('Upper, Mon, Nov 16'), findsOneWidget);

      await app.stop(tester);
    });

    testWidgets('is skipped from Programs, so the next day is today', (
      tester,
    ) async {
      final app = world();
      await app.start(tester);
      await openTab(tester, 'Programs');

      await tapText(tester, 'Skip');

      expect(active(app).nextDayIndex, 1);
      expect(active(app).nextDate, wednesday);
      expect(find.text('Start Lower'), findsOneWidget);
      await openTab(tester, 'Today');
      expect(find.text('Start Lower'), findsOneWidget);

      await app.stop(tester);
    });
  });

  group('the builder', () {
    Finder field(String label) => find.descendant(
      of: find.widgetWithText(ForgeTextField, label),
      matching: find.byType(TextField),
    );

    Future<void> addExercise(WidgetTester tester, String name) async {
      await tapOn(tester, find.text('Add exercises').last);
      await tapText(tester, name);
      await tapText(tester, 'Add 1 exercise');
    }

    testWidgets('builds a program day by day with its targets', (tester) async {
      final app = TrainingWorld(exercises: exercises);
      await app.start(tester);
      await openTab(tester, 'Programs');
      await tapText(tester, 'New program');

      await tester.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'Push Pull',
      );
      await addExercise(tester, 'Bench Press');
      await tapOn(tester, find.text('Sets').first);
      await tester.enterText(field('Sets'), '4');
      await tester.enterText(field('Reps from'), '6');
      await tester.enterText(field('Reps to'), '8');
      await tapText(tester, 'Done');

      await tapText(tester, 'Day');
      await tester.enterText(find.byType(TextField).last, 'Pull');
      await tapOn(tester, inDialog('Save'));
      await addExercise(tester, 'Barbell Row');

      // Leaving asks first; keeping on keeps both days.
      await tapOn(tester, find.bySemanticsLabel('Back'));
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapText(tester, 'Keep editing');
      expect(find.byType(ProgramBuilderPage), findsOneWidget);
      expect(find.text('Barbell Row'), findsOneWidget);

      await tapOn(
        tester,
        find.descendant(
          of: find.byType(ForgeAppBar),
          matching: find.text('Save'),
        ),
      );

      final saved = app.programs.programs.values.single;
      expect(saved.name, 'Push Pull');
      expect(saved.days.map((day) => day.name), ['', 'Pull']);
      expect(
        saved.days.first.items.single,
        (isA<ProgramItem>()
            .having((i) => i.exerciseId, 'exercise', 'bench')
            .having((i) => i.sets, 'sets', 4)
            .having((i) => i.repMin, 'from', 6)
            .having((i) => i.repMax, 'to', 8)),
      );
      expect(saved.days.last.items.single.exerciseId, 'row');
      expect(find.byType(ProgramBuilderPage), findsNothing);
      expect(find.text('Push Pull'), findsWidgets);

      await app.stop(tester);
    });
  });
}
