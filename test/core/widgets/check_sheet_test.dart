import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/check_sheet.dart';

import '../../component_harness.dart';

void main() {
  bool checked(WidgetTester tester, String label) => tester
      .widget<ForgeCheckbox>(
        find.descendant(
          of: find.widgetWithText(CheckRow, label),
          matching: find.byType(ForgeCheckbox),
        ),
      )
      .value;

  /// A button opening a check sheet of four days, Tue ticked; [onResult]
  /// gets what it completes with.
  Future<void> open(
    WidgetTester tester,
    ValueChanged<Set<String>?> onResult,
  ) async {
    await pumpComponent(
      tester,
      Builder(
        builder: (context) => ForgeButton(
          label: 'Open',
          onPressed: () async => onResult(
            await showCheckSheet(
              context,
              title: 'Days',
              values: const ['Mon', 'Tue', 'Wed', 'Thu'],
              selected: const {'Tue'},
              labelOf: (day) => day,
              saveLabel: 'Save',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a row ticks and unticks from anywhere on it', (tester) async {
    await open(tester, (_) {});
    expect(find.byType(CheckRow), findsNWidgets(4));
    expect(checked(tester, 'Tue'), isTrue);
    expect(checked(tester, 'Mon'), isFalse);

    await tester.tap(find.text('Mon'));
    await tester.pump();
    expect(checked(tester, 'Mon'), isTrue);

    await tester.tap(find.byType(ForgeCheckbox).first);
    await tester.pump();
    expect(checked(tester, 'Mon'), isFalse);
  });

  testWidgets('Save completes with the ticked values in their order', (
    tester,
  ) async {
    Set<String>? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.text('Thu'));
    await tester.tap(find.text('Mon'));
    await tester.tap(find.text('Tue'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.toList(), ['Mon', 'Thu']);
    expect(find.byType(ForgeBottomSheet), findsNothing);
  });

  testWidgets('closing without Save changes nothing', (tester) async {
    var result = <String>{'unset'};
    await open(tester, (value) => result = value ?? {});
    await tester.tap(find.text('Mon'));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isEmpty);
  });
}
