import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/choice_sheet.dart';

import '../../component_harness.dart';

void main() {
  testWidgets('a choice row marks its choice and reports a tap', (
    tester,
  ) async {
    var taps = 0;
    await pumpComponent(
      tester,
      ChoiceRow(label: 'By feel', selected: true, onTap: () => taps++),
    );

    expect(tester.widget<RadioMark>(find.byType(RadioMark)).selected, isTrue);
    await tester.tap(find.text('By feel'));
    expect(taps, 1);
  });

  testWidgets('a choice setting row shows its value and picks in a sheet', (
    tester,
  ) async {
    int? picked;
    await pumpComponent(
      tester,
      ChoiceSettingRow<int>(
        title: 'Repeat',
        values: const [1, 2, 4],
        selected: 2,
        labelOf: (weeks) => 'Every $weeks',
        onChanged: (weeks) => picked = weeks,
      ),
    );
    expect(find.text('Every 2'), findsOneWidget);

    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgeBottomSheet), findsOneWidget);
    expect(find.byType(ChoiceRow), findsNWidgets(3));
    final marks = tester.widgetList<RadioMark>(find.byType(RadioMark));
    expect(marks.map((mark) => mark.selected), [false, true, false]);

    await tester.tap(find.text('Every 4'));
    await tester.pumpAndSettle();
    expect(picked, 4);
    expect(find.byType(ForgeBottomSheet), findsNothing);
  });

  testWidgets('closing the sheet picks nothing', (tester) async {
    int? picked;
    await pumpComponent(
      tester,
      ChoiceSettingRow<int>(
        title: 'Repeat',
        values: const [1, 2],
        selected: 1,
        labelOf: (weeks) => 'Every $weeks',
        onChanged: (weeks) => picked = weeks,
      ),
    );
    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
