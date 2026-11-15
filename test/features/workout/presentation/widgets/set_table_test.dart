import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_table.dart';

import '../../../../component_harness.dart';

void main() {
  testWidgets('a row per set, its effort and record as tags', (tester) async {
    await pumpComponent(
      tester,
      const SetTable(
        name: 'Bench Press',
        rows: [
          SetTableRow(label: 'W', values: '40 kg × 10'),
          SetTableRow(
            label: '1',
            values: '82.5 kg × 8',
            effort: 'RIR 2',
            record: true,
          ),
        ],
      ),
    );

    expect(find.text('40 kg × 10'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('RIR 2'), findsOneWidget);
    final record = tester.widget<ForgeTag>(
      find.widgetWithText(ForgeTag, 'record'),
    );
    expect(record.kind, ForgeTagKind.record);
    expect(record.icon, ForgeIcons.emojiEvents);
  });

  testWidgets('drops, notes, the type and the group letter', (tester) async {
    await pumpComponent(
      tester,
      const SetTable(
        name: 'Back Squat',
        group: 'A1',
        type: 'Weighted bodyweight',
        note: 'Belt on the top sets',
        rows: [
          SetTableRow(
            label: '4D',
            values: '82.5 kg × 6',
            effort: 'Failed',
            note: 'Paused at the bottom',
            drops: ['60 kg × 8', '40 kg × 10'],
          ),
        ],
      ),
    );

    for (final text in [
      'A1',
      'Weighted bodyweight',
      'Belt on the top sets',
      'Paused at the bottom',
      '60 kg × 8',
      'Drop 1',
      'Drop 2',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    final drop = tester.widget<ForgeTag>(
      find.widgetWithText(ForgeTag, 'Drop 1'),
    );
    expect(drop.kind, ForgeTagKind.plain);
    // Under its set's values.
    expect(
      tester.getTopLeft(find.text('60 kg × 8')).dx,
      tester.getTopLeft(find.text('82.5 kg × 6')).dx,
    );
  });

  testWidgets('the edit form types values, adds a set and opens the menu', (
    tester,
  ) async {
    final weight = TextEditingController(text: '80');
    final reps = TextEditingController(text: '8');
    addTearDown(weight.dispose);
    addTearDown(reps.dispose);
    final typed = <String>[];
    var added = 0;
    var removed = 0;
    var toggled = 0;
    var options = 0;
    var effort = 0;
    await pumpComponent(
      tester,
      SetTable.edit(
        name: 'Bench Press',
        rows: [
          SetTableEditRow(
            label: '1',
            semanticLabel: 'Set 1',
            done: true,
            onToggle: () => toggled++,
            onOptions: (_) => options++,
            onEffort: () => effort++,
            effort: 'Moderate',
            inputs: [
              SetTableInput(
                label: 'Weight',
                controller: weight,
                onChanged: typed.add,
                wide: true,
              ),
              SetTableInput(
                label: 'Reps',
                controller: reps,
                onChanged: typed.add,
              ),
            ],
          ),
        ],
        menu: [
          ForgeMenuItem(
            label: 'Remove',
            onTap: () => removed++,
            destructive: true,
          ),
        ],
        onAddSet: () => added++,
      ),
    );

    final boxes = tester
        .widgetList<ForgeNumberField>(find.byType(ForgeNumberField))
        .map((box) => (box.unit, box.boxSize));
    expect(boxes, [(null, const Size(70, 34)), (null, const Size(50, 34))]);
    expect(find.text('Moderate'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '82.5');
    expect(typed, ['82.5']);

    await tester.tap(find.text('Add set'));
    expect(added, 1);

    await tester.tap(find.text('1'));
    await tester.longPress(find.text('1'));
    await tester.tap(find.text('Moderate'));
    expect((toggled, options, effort), (1, 1, 1));

    await tester.tap(find.bySemanticsLabel('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed, 1);
  });
}
