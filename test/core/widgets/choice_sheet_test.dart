import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/choice_sheet.dart';

import '../../component_harness.dart';

void main() {
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
    final grid = tester.widget<ChoiceGrid>(find.byType(ChoiceGrid));
    expect(grid.form, ChoiceListForm.inline);
    expect(grid.options.map((option) => option.label), [
      'Every 1',
      'Every 2',
      'Every 4',
    ]);
    final marks = tester.widgetList<RadioMark>(find.byType(RadioMark));
    expect(marks.map((mark) => mark.selected), [false, true, false]);

    await tester.tap(find.text('Every 4'));
    await tester.pumpAndSettle();
    expect(picked, 4);
    expect(find.byType(ForgeBottomSheet), findsNothing);
  });

  testWidgets('values with a detail line are stacked rows', (tester) async {
    await pumpComponent(
      tester,
      ChoiceSettingRow<int>(
        title: 'Repeat',
        values: const [1, 2],
        selected: 1,
        labelOf: (weeks) => 'Every $weeks',
        detailOf: (weeks) => weeks == 2 ? 'Every other week' : null,
        onChanged: (_) {},
      ),
    );
    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    final grid = tester.widget<ChoiceGrid>(find.byType(ChoiceGrid));
    expect(grid.form, ChoiceListForm.stacked);
    expect(grid.options.map((option) => option.hint), [
      null,
      'Every other week',
    ]);
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
