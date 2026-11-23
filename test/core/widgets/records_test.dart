import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/records.dart';

import '../../component_harness.dart';

void main() {
  testWidgets('the biggest record says New record over its value', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const RecordHighlight(
        value: '82.5 kg × 8',
        line: 'Bench Press · e1RM 104 kg · +2.5 kg',
      ),
    );

    expect(find.text('New record'), findsOneWidget);
    expect(find.text('82.5 kg × 8'), findsOneWidget);
  });

  testWidgets('records are counted over rows with their set and gain tag', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const RecordList(
        records: [
          RecordItem(
            name: 'Overhead Press',
            detail: 'Heaviest weight · Best e1RM',
            value: '50 kg × 8',
            gain: '+2.5 kg',
          ),
          RecordItem(
            name: 'Pull-up',
            detail: 'Most reps',
            value: '12 reps',
            gain: '+2 reps',
          ),
        ],
      ),
    );

    expect(find.text('2 new records'), findsOneWidget);
    expect(find.text('Overhead Press'), findsOneWidget);
    expect(
      find.text('Heaviest weight · Best e1RM · 50 kg × 8', findRichText: true),
      findsOneWidget,
    );
    final gain = tester.widget<ForgeTag>(
      find.widgetWithText(ForgeTag, '+2 reps'),
    );
    expect(gain.kind, ForgeTagKind.record);
  });

  testWidgets('one record says 1 new record', (tester) async {
    await pumpComponent(
      tester,
      const RecordList(
        records: [
          RecordItem(
            name: 'Bench Press',
            detail: 'Best e1RM',
            value: '82.5 kg × 6',
            gain: '+1 kg',
          ),
        ],
      ),
    );

    expect(find.text('1 new record'), findsOneWidget);
  });

  testWidgets('no record after the first workout says records start now', (
    tester,
  ) async {
    await pumpComponent(tester, const RecordList.none());

    expect(find.text('Your first marks are set'), findsOneWidget);
  });

  testWidgets('no record later says how close the best came', (tester) async {
    await pumpComponent(
      tester,
      const RecordList.none(closest: 'Bench Press was 2.5 kg off your best.'),
    );

    expect(find.text('No new records this time'), findsOneWidget);
    expect(find.text('Bench Press was 2.5 kg off your best.'), findsOneWidget);
    expect(find.text('Your first marks are set'), findsNothing);
  });

  testWidgets('a long exercise name stays on one line', (tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: 260,
        child: RecordList(
          records: [
            RecordItem(
              name: 'Single-Arm Dumbbell Overhead Press',
              detail: 'Best weight for 8 reps',
              value: '22.5 kg × 8',
              gain: '+2.5 kg',
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
