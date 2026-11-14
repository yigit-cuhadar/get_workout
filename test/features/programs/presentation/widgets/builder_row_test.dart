import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/presentation/widgets/builder_row.dart';

import '../../../../component_harness.dart';

void main() {
  Widget list(List<BuilderRow> rows) => CustomScrollView(
    slivers: [
      BuilderCard(
        sliver: SliverReorderableList(
          itemCount: rows.length,
          onReorderItem: (_, _) {},
          itemBuilder: (_, index) =>
              KeyedSubtree(key: ValueKey(index), child: rows[index]),
        ),
      ),
    ],
  );

  testWidgets('a chip tap edits its value; the menu runs its actions', (
    tester,
  ) async {
    final edited = <String>[];
    var removed = 0;
    await pumpComponent(
      tester,
      list([
        BuilderRow(
          index: 0,
          name: 'Bench Press',
          values: [
            for (final (label, value) in [
              ('Sets', '4'),
              ('Reps', '6–8'),
              ('Rest', '2:00'),
            ])
              BuilderValue(
                label: label,
                value: value,
                onTap: () => edited.add(label),
              ),
          ],
          menu: [
            ForgeMenuItem(
              label: 'Remove',
              onTap: () => removed++,
              destructive: true,
            ),
          ],
          divided: false,
        ),
      ]),
    );

    await tester.tap(find.text('6–8'));
    await tester.tap(find.text('Rest'));
    expect(edited, ['Reps', 'Rest']);

    await tester.tap(find.bySemanticsLabel('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed, 1);
  });

  testWidgets('a group carries the accent rule, its header on the first', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      list([
        for (final (i, name) in ['Lateral Raise', 'Triceps Pushdown'].indexed)
          BuilderRow(
            index: i,
            name: name,
            values: const [],
            menu: const [],
            grouped: true,
            divided: i == 0,
            groupHeader: i == 0 ? 'Superset · rest after both 1:30' : null,
          ),
      ]),
    );

    expect(find.text('Superset · rest after both 1:30'), findsOneWidget);
    final context = tester.element(find.text('Lateral Raise'));
    final accent = ForgeStyle.of(context).colors.accent;
    final rules = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where(
          (d) =>
              d.border is Border &&
              (d.border! as Border).left.color == accent &&
              (d.border! as Border).left.width == 3,
        );
    expect(rules, hasLength(2));
  });

  testWidgets('a chip is drawn 24px and takes taps across 44px', (
    tester,
  ) async {
    var taps = 0;
    await pumpComponent(
      tester,
      list([
        BuilderRow(
          index: 0,
          name: 'Bench Press',
          values: [
            BuilderValue(label: 'Sets', value: '4', onTap: () => taps++),
          ],
          menu: const [],
          divided: false,
        ),
      ]),
    );

    final chip = find.ancestor(
      of: find.text('Sets'),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 24,
      ),
    );
    expect(tester.getSize(chip).height, 24);
    final rect = tester.getRect(chip);
    await tester.tapAt(rect.topCenter - const Offset(0, 9));
    await tester.tapAt(rect.bottomCenter + const Offset(0, 9));
    expect(taps, 2);
  });

  testWidgets('the issues show under the chips', (tester) async {
    await pumpComponent(
      tester,
      list([
        const BuilderRow(
          index: 0,
          name: 'Exercise unavailable',
          values: [],
          menu: [],
          issues: ['Replace it with another exercise.'],
        ),
      ]),
    );

    expect(find.text('Replace it with another exercise.'), findsOneWidget);
  });
}
