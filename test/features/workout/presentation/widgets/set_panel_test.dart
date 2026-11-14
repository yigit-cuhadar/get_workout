import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_panel.dart';

const _labels = SetPanelLabels(
  log: 'Log set',
  done: 'Done',
  options: 'Set options',
  addDrop: 'Add drop',
  removeDrop: 'Remove drop',
  plates: 'Plates',
);

Future<void> _pump(WidgetTester tester, SetPanel panel) => tester.pumpWidget(
  MaterialApp(
    theme: AppPreset.slate.lightTheme(),
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: panel),
    ),
  ),
);

SetPanelValue _value(
  double? value,
  String unit, {
  ValueChanged<double?>? onChanged,
  bool signed = false,
  bool invalid = false,
}) => SetPanelValue(
  value: value,
  unit: unit,
  step: unit == 'kg' ? 2.5 : 1,
  min: 0,
  onChanged: onChanged ?? (_) {},
  signed: signed,
  invalid: invalid,
);

void main() {
  testWidgets('the set, its values and Log set', (tester) async {
    var logged = 0;
    var options = 0;
    final weights = <double?>[];
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · set 3 of 4',
        details: const ['Last time: 80 kg × 8'],
        labels: _labels,
        values: [
          _value(82.5, 'kg', onChanged: weights.add),
          _value(8, 'reps'),
        ],
        onOptions: () => options++,
        onLog: () => logged++,
      ),
    );
    expect(find.text('Bench Press · set 3 of 4'), findsOneWidget);
    expect(find.text('Last time: 80 kg × 8'), findsOneWidget);
    expect(find.byType(StepperField), findsNWidgets(2));
    await tester.tap(find.text('Log set'));
    await tester.tap(find.bySemanticsLabel('Set options'));
    expect(logged, 1);
    expect(options, 1);
    // The weight's plus button.
    final plus = find.descendant(
      of: find.byType(StepperField).first,
      matching: find.byType(ForgeIcon),
    );
    await tester.tap(plus.last);
    expect(weights.last, 85);
    // The tick before Log set.
    expect(
      tester.widget<ForgeButton>(find.byType(ForgeButton)).leadingIcon,
      ForgeIcons.check,
    );
  });

  testWidgets('a load added to the body shows its sign', (tester) async {
    await _pump(
      tester,
      SetPanel(
        title: 'Pull-up · set 2 of 3',
        details: const [],
        labels: _labels,
        values: [_value(10, 'kg added', signed: true), _value(6, 'reps')],
        onOptions: () {},
        onLog: () {},
      ),
    );
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('the plate button opens the breakdown; none without it', (
    tester,
  ) async {
    BuildContext? at;
    Future<void> pump({required bool plates}) => _pump(
      tester,
      SetPanel(
        title: 'Bench Press · set 3 of 4',
        details: const [],
        labels: _labels,
        values: [_value(82.5, 'kg'), _value(8, 'reps')],
        onPlates: plates ? (button) => at = button : null,
        onOptions: () {},
        onLog: () {},
      ),
    );
    await pump(plates: false);
    expect(find.bySemanticsLabel('Plates'), findsNothing);
    await pump(plates: true);
    final button = find.bySemanticsLabel('Plates');
    expect(tester.getSize(button), const Size.square(44));
    // Between the weight and the reps.
    expect(
      tester.getCenter(button).dx,
      greaterThan(tester.getCenter(find.byType(StepperField).first).dx),
    );
    expect(
      tester.getCenter(button).dx,
      lessThan(tester.getCenter(find.byType(StepperField).last).dx),
    );
    await tester.tap(button);
    expect(at, isNotNull);
  });

  testWidgets('a missing value rings its field, says why, Log set off', (
    tester,
  ) async {
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · set 3 of 4',
        details: const [],
        labels: _labels,
        values: [_value(null, 'kg', invalid: true), _value(8, 'reps')],
        error: "Enter the set's values first.",
        onOptions: () {},
        onLog: null,
      ),
    );
    // Under the row of fields, not under one of them.
    final error = find.widgetWithText(
      StepperFieldError,
      "Enter the set's values first.",
    );
    expect(error, findsOneWidget);
    expect(
      tester.getTopLeft(error).dx,
      tester.getTopLeft(find.byType(StepperField).first).dx,
    );
    expect(
      tester.getTopLeft(error).dy,
      greaterThan(tester.getBottomLeft(find.byType(StepperField).last).dy),
    );
    final fields = tester.widgetList<StepperField>(find.byType(StepperField));
    expect(fields.map((field) => field.invalid), [true, false]);
    final log = tester.widget<ForgeButton>(find.byType(ForgeButton).last);
    expect(log.onPressed, isNull);
  });

  testWidgets('a done set shows Done and its effort', (tester) async {
    var unticked = 0;
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · set 1 of 4',
        details: const [],
        labels: _labels,
        values: [_value(82.5, 'kg'), _value(8, 'reps')],
        done: true,
        effort: const Text('Set 1 · how hard was it?'),
        onOptions: () {},
        onLog: () => unticked++,
      ),
    );
    expect(find.text('Log set'), findsNothing);
    expect(find.text('Set 1 · how hard was it?'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(unticked, 1);
  });

  testWidgets('a drop set: drops under the values, remove and add', (
    tester,
  ) async {
    final removed = <int>[];
    var added = 0;
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · Drop set 4 of 4',
        details: const [],
        labels: _labels,
        values: [_value(82.5, 'kg'), _value(6, 'reps')],
        drops: [
          for (final (i, kg) in [60.0, 40.0].indexed)
            SetPanelDrop(
              label: 'Drop ${i + 1}',
              values: [_value(kg, 'kg'), _value(8, 'reps')],
              onRemove: () => removed.add(i),
            ),
        ],
        onAddDrop: () => added++,
        onOptions: () {},
        onLog: () {},
      ),
    );
    expect(find.text('Drop 2'), findsOneWidget);
    final fields = tester.widgetList<StepperField>(find.byType(StepperField));
    expect(fields.map((field) => field.compact), [
      false,
      false,
      true,
      true,
      true,
      true,
    ]);
    // A drop row keeps the compact fields' height.
    final remove = find.bySemanticsLabel('Remove drop');
    expect(tester.getSize(remove.first), const Size(30, 32));
    await tester.tap(remove.last);
    // Its band reaches past the drawn box.
    await tester.tapAt(tester.getTopRight(remove.first) + const Offset(6, 0));
    await tester.tap(find.text('Add drop'));
    expect(removed, [1, 0]);
    expect(added, 1);
    final addDrop = tester.widget<ForgeButton>(
      find.widgetWithText(ForgeButton, 'Add drop'),
    );
    expect(
      (addDrop.leadingIcon, addDrop.variant, addDrop.size),
      (ForgeIcons.add, ForgeButtonVariant.text, ForgeButtonSize.small),
    );
  });

  testWidgets('showing: something else in place of the entry', (tester) async {
    await _pump(
      tester,
      const SetPanel.showing(child: Text('How hard was set 3?')),
    );
    expect(find.text('How hard was set 3?'), findsOneWidget);
    expect(find.byType(StepperField), findsNothing);
  });
}
