import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/tap_band.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_panel.dart';

const _labels = SetPanelLabels(
  log: 'Log set',
  done: 'Done',
  next: 'Next',
  options: 'Set options',
  addDrop: 'Add drop',
  removeDrop: 'Remove drop',
  plates: 'Plates',
);

/// [height] caps the panel, as the workout screen gives it a share of the
/// page.
Future<void> _pump(WidgetTester tester, SetPanel panel, {double? height}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.slate.lightTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height ?? double.infinity),
              child: panel,
            ),
          ),
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

  testWidgets('typing the weight, Next types the reps and Done closes the '
      'keyboard; a drop\'s values come next', (tester) async {
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · set 3 of 4',
        details: const [],
        labels: _labels,
        values: [_value(82.5, 'kg'), _value(8, 'reps')],
        drops: [
          SetPanelDrop(
            label: 'Drop 1',
            values: [_value(60, 'kg'), _value(6, 'reps')],
            onRemove: () {},
          ),
        ],
        onAddDrop: () {},
        onOptions: () {},
        onLog: () {},
      ),
    );
    bool typing(int i) => tester
        .widget<EditableText>(find.byType(EditableText).at(i))
        .focusNode
        .hasFocus;

    await tester.tap(find.text('82.5'));
    await tester.pump();
    expect(typing(0), isTrue);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(typing(1), isTrue);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(typing(2), isTrue);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    expect([for (var i = 0; i < 4; i++) typing(i)], everyElement(isFalse));
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

  testWidgets(
    'a missing value rings its field and says why; Log set stays on',
    (tester) async {
      var logged = 0;
      await _pump(
        tester,
        SetPanel(
          title: 'Bench Press · set 3 of 4',
          details: const [],
          labels: _labels,
          values: [_value(null, 'kg', invalid: true), _value(8, 'reps')],
          error: "Enter the set's values first.",
          onOptions: () {},
          onLog: () => logged++,
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
      await tester.tap(find.text('Log set'));
      expect(logged, 1);
    },
  );

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
    final box = find.ancestor(
      of: remove.first,
      matching: find.byType(TapBandIconButton),
    );
    expect(tester.getSize(box), const Size(30, 32));
    await tester.tap(remove.last);
    // Its band reaches past the laid-out box.
    await tester.tapAt(tester.getTopRight(box) + const Offset(6, 0));
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

  testWidgets('a drop scrolled out of view takes no taps on its band', (
    tester,
  ) async {
    final removed = <int>[];
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · Drop set 4 of 4',
        details: const [],
        labels: _labels,
        values: [_value(82.5, 'kg'), _value(6, 'reps')],
        drops: [
          for (var i = 0; i < 6; i++)
            SetPanelDrop(
              label: 'Drop ${i + 1}',
              values: [_value(60, 'kg'), _value(8, 'reps')],
              onRemove: () => removed.add(i),
            ),
        ],
        onAddDrop: () {},
        onOptions: () {},
        onLog: () {},
      ),
      height: 340,
    );
    final scroll = find.byType(SingleChildScrollView);
    final viewport = tester.getRect(scroll);
    final bands = find.descendant(of: scroll, matching: find.byType(TapBand));
    // Scrolled until the first drop is above the scrolling part and the
    // second is cut by its top edge.
    final firstTop = tester.getTopLeft(bands.at(0)).dy;
    final secondTop = tester.getTopLeft(bands.at(1)).dy;
    await tester.drag(scroll, Offset(0, viewport.top - secondTop - 10));
    await tester.pumpAndSettle();
    expect(tester.getRect(bands.at(0)).bottom, lessThan(viewport.top));
    expect(tester.getRect(bands.at(1)).top, lessThan(viewport.top));
    expect(tester.getRect(bands.at(1)).bottom, greaterThan(viewport.top));
    expect(firstTop, lessThan(secondTop));
    // On the first drop's place, and on the second's band past its box.
    await tester.tapAt(tester.getCenter(bands.at(0)));
    await tester.tapAt(
      tester.getRect(bands.at(1)).centerRight + const Offset(6, 0),
    );
    expect(removed, isEmpty);
    // A drop drawn whole keeps its band.
    final third = tester.getRect(bands.at(2));
    expect(viewport.contains(third.topLeft), isTrue);
    await tester.tapAt(third.centerRight + const Offset(6, 0));
    expect(removed, [2]);
  });

  testWidgets('showing: something else in place of the entry', (tester) async {
    await _pump(
      tester,
      const SetPanel.showing(child: Text('How hard was set 3?')),
    );
    expect(find.text('How hard was set 3?'), findsOneWidget);
    expect(find.byType(StepperField), findsNothing);
  });

  testWidgets('without details the values sit right under the title; '
      'the options keep their 44px band', (tester) async {
    var options = 0;
    await _pump(
      tester,
      SetPanel(
        title: 'Squat · set 1 of 3',
        details: const [],
        values: [_value(null, 'kg'), _value(null, 'reps')],
        labels: _labels,
        onOptions: () => options++,
        onLog: () {},
      ),
    );
    final title = tester.getRect(find.text('Squat · set 1 of 3'));
    final field = tester.getRect(find.byType(StepperField).first);
    expect(field.top - title.bottom, closeTo(12, 1));
    final icon = tester.getCenter(find.bySemanticsLabel('Set options'));
    await tester.tapAt(icon + const Offset(0, 18));
    expect(options, 1);
  });

  testWidgets('a description in the body font over the details', (
    tester,
  ) async {
    await _pump(
      tester,
      SetPanel(
        title: 'Bench Press · Warm-up 1 of 2',
        description: 'A lighter set to get ready.',
        details: const [],
        values: [_value(40, 'kg'), _value(8, 'reps')],
        labels: _labels,
        onOptions: () {},
        onLog: () {},
      ),
    );
    final line = tester.widget<Text>(find.text('A lighter set to get ready.'));
    final theme = Theme.of(tester.element(find.byType(SetPanel)));
    expect(line.style!.fontFamily, theme.textTheme.labelMedium!.fontFamily);
  });
}
