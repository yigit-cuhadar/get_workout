import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/workout/presentation/widgets/exercise_card.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_bubble.dart';

Future<void> _pump(WidgetTester tester, ExerciseCard card) => tester.pumpWidget(
  MaterialApp(
    theme: AppPreset.slate.lightTheme(),
    home: Scaffold(body: SingleChildScrollView(child: card)),
  ),
);

SetBubble _bubble(String label) =>
    SetBubble(label: label, semanticLabel: label, onTap: () {});

ExerciseCardSets _sets(
  List<String> working, {
  List<String> warmups = const [],
}) => ExerciseCardSets(
  warmups: [for (final l in warmups) _bubble(l)],
  working: [for (final l in working) _bubble(l)],
  add: SetBubble.add(semanticLabel: 'Add set', onTap: () {}),
);

void main() {
  testWidgets('collapsed: a tap opens the exercise, ⋯ its menu', (
    tester,
  ) async {
    var opened = 0;
    BuildContext? menuAt;
    await _pump(
      tester,
      ExerciseCard(
        optionsLabel: 'Exercise options',
        items: [
          ExerciseCardItem(
            name: 'Overhead Press',
            count: '0/3',
            progress: 0,
            onTap: () => opened++,
            onOptions: (button) => menuAt = button,
          ),
        ],
      ),
    );
    expect(find.text('0/3'), findsOneWidget);
    await tester.tap(find.text('Overhead Press'));
    await tester.tap(find.bySemanticsLabel('Exercise options'));
    expect(opened, 1);
    expect(menuAt, isNotNull);
  });

  testWidgets('open: its goal, last time, note and bubbles', (tester) async {
    await _pump(
      tester,
      ExerciseCard(
        form: ExerciseCardForm.open,
        optionsLabel: 'Exercise options',
        items: [
          ExerciseCardItem(
            name: 'Bench Press',
            count: '3/5',
            progress: 0.6,
            details: const ['Goal: 4 × 6–8', 'Use the flat bench'],
            sets: _sets(['1', '2', '3', '4'], warmups: ['W']),
            onOptions: (_) {},
          ),
        ],
      ),
    );
    expect(find.text('Goal: 4 × 6–8'), findsOneWidget);
    expect(find.text('Use the flat bench'), findsOneWidget);
    expect(find.byType(SetBubble), findsNWidgets(6));
  });

  testWidgets('a group shows its label and letters; open, a round grid', (
    tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      ExerciseCard(
        form: ExerciseCardForm.open,
        group: 'Superset A',
        optionsLabel: 'Exercise options',
        items: [
          for (final (i, name) in ['Lateral Raise', 'Triceps Pushdown'].indexed)
            ExerciseCardItem(
              name: name,
              count: '0/3',
              progress: 0,
              letter: 'A${i + 1}',
              sets: _sets(['1', '2', '3']),
              onTap: () => selected.add(i),
              onOptions: (_) {},
            ),
        ],
      ),
    );
    expect(find.text('Superset A'), findsOneWidget);
    // Each letter leads its line and its row of bubbles.
    expect(find.text('A1'), findsNWidgets(2));
    expect(find.byType(SetBubble), findsNWidgets(8));
    // A round's bubbles share a column.
    final first = find.byType(SetBubble).at(0);
    final below = find.byType(SetBubble).at(4);
    expect(tester.getTopLeft(first).dx, tester.getTopLeft(below).dx);
    await tester.tap(find.text('Triceps Pushdown'));
    expect(selected, [1]);
  });

  testWidgets('lines: one short line each, no menu', (tester) async {
    await _pump(
      tester,
      ExerciseCard(
        form: ExerciseCardForm.line,
        optionsLabel: 'Exercise options',
        items: [
          ExerciseCardItem(
            name: 'Incline Dumbbell Press',
            count: '0/3',
            progress: 0,
            onOptions: (_) {},
          ),
        ],
      ),
    );
    expect(find.bySemanticsLabel('Exercise options'), findsNothing);
    expect(tester.getSize(find.byType(ExerciseCard)).height, lessThan(50));
  });

  testWidgets('wrapLine wraps each line but not its menu', (tester) async {
    final wrapped = <int>[];
    await _pump(
      tester,
      ExerciseCard(
        optionsLabel: 'Exercise options',
        wrapLine: (item, line) {
          wrapped.add(item);
          return KeyedSubtree(key: ValueKey('line $item'), child: line);
        },
        items: [
          for (final name in ['A', 'B'])
            ExerciseCardItem(
              name: name,
              count: '0/3',
              progress: 0,
              onOptions: (_) {},
            ),
        ],
      ),
    );
    expect(wrapped, [0, 1]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('line 0')),
        matching: find.bySemanticsLabel('Exercise options'),
      ),
      findsNothing,
    );
  });
}
