import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/effort_question.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';

import '../../../../component_harness.dart';

void main() {
  const byFeel = [
    ChoiceOption(label: 'Easy', hint: '4+ reps left'),
    ChoiceOption(label: 'Moderate', hint: '2–3 reps left'),
    ChoiceOption(label: 'Hard', hint: '1 rep left'),
    ChoiceOption(label: 'Max', hint: 'No reps left'),
    ChoiceOption(label: 'Failed', hint: 'last rep missed'),
  ];

  Widget question({
    int? selected,
    ValueChanged<int>? onSelected,
    VoidCallback? onHelp,
    EffortRest? rest,
    Widget? tip,
  }) => EffortQuestion(
    question: rest == null ? 'How hard was it?' : 'How hard was set 3?',
    values: rest == null ? 'Set 1 done · 82.5 kg × 8' : '82.5 kg × 8',
    options: byFeel,
    selected: selected,
    onSelected: onSelected ?? (_) {},
    onHelp: onHelp ?? () {},
    rest: rest,
    tip: tip,
  );

  testWidgets('a tap on a row answers with its index', (tester) async {
    int? picked;
    await pumpComponent(tester, question(onSelected: (i) => picked = i));

    expect(find.text('2–3 reps left'), findsOneWidget);
    await tester.tap(find.text('Hard'));
    expect(picked, 2);
  });

  testWidgets('the picked row reads as checked', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpComponent(tester, question(selected: 1));

    expect(
      tester.getSemantics(find.text('Moderate')),
      matchesSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: 'Moderate\n2–3 reps left',
      ),
    );
    semantics.dispose();
  });

  testWidgets('the help calls back; the question has no Skip', (tester) async {
    var helped = 0;
    await pumpComponent(tester, question(onHelp: () => helped++));

    await tester.tap(find.bySemanticsLabel('Explain'));
    expect(helped, 1);
    expect(find.textContaining('Skip'), findsNothing);
  });

  testWidgets('the tip scrolls under the steps, never hiding one', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      SizedBox(
        height: 420,
        child: question(
          rest: EffortRest(
            time: '1:45',
            progress: 0.85,
            onAddTime: () {},
            onSkip: () {},
          ),
          tip: const SizedBox(height: 200, child: Text('The tip')),
        ),
      ),
    );

    final panel = tester.getRect(find.byType(EffortQuestion));
    for (final step in ['Easy', 'Moderate', 'Hard', 'Max', 'Failed']) {
      final row = tester.getRect(find.text(step));
      expect(row.bottom, lessThanOrEqualTo(panel.bottom), reason: step);
    }
    expect(
      tester.getTopLeft(find.text('The tip')).dy,
      greaterThan(tester.getBottomLeft(find.text('Failed')).dy),
    );
    await tester.drag(find.text('Failed'), const Offset(0, -300));
    await tester.pump();
    expect(
      tester.getRect(find.text('The tip')).bottom,
      lessThanOrEqualTo(panel.bottom),
    );
  });

  testWidgets('without a rest the set comes first and no rest line shows', (
    tester,
  ) async {
    await pumpComponent(tester, question());

    expect(find.byType(RestTrack), findsNothing);
    final done = tester.getTopLeft(find.text('Set 1 done · 82.5 kg × 8'));
    final asked = tester.getTopLeft(find.text('How hard was it?'));
    expect(done.dy, lessThan(asked.dy));
  });

  testWidgets('with a rest its line sits on top with +15 s and Skip rest', (
    tester,
  ) async {
    var added = 0;
    var skippedRest = 0;
    await pumpComponent(
      tester,
      question(
        rest: EffortRest(
          time: '1:45',
          progress: 0.85,
          onAddTime: () => added++,
          onSkip: () => skippedRest++,
        ),
      ),
    );

    expect(find.text('Rest 1:45'), findsOneWidget);
    expect(find.byType(RestTrack), findsOneWidget);
    final asked = tester.getTopLeft(find.text('How hard was set 3?'));
    final values = tester.getTopLeft(find.text('82.5 kg × 8'));
    expect(asked.dy, lessThan(values.dy));

    await tester.tap(find.text('+15 s'));
    await tester.tap(find.text('Skip rest'));
    expect((added, skippedRest), (1, 1));
    expect(find.text('Skip'), findsNothing);
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('at ${scale}x text the rest line scales to fit', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: question(
            rest: EffortRest(
              time: '1:45',
              progress: 0.85,
              onAddTime: () {},
              onSkip: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(RestTrack)).width,
        greaterThanOrEqualTo(RestLine.minTrack),
      );
    });
  }
}
