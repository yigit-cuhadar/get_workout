import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/workout/presentation/widgets/effort_question.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';

import '../../../../component_harness.dart';

void main() {
  const byFeel = [
    EffortOption(label: 'Easy', meaning: '4+ reps left'),
    EffortOption(label: 'Moderate', meaning: '2–3 reps left'),
    EffortOption(label: 'Hard', meaning: '1 rep left'),
    EffortOption(label: 'Max', meaning: 'No reps left'),
    EffortOption(label: 'Failed', meaning: 'last rep missed'),
  ];

  Widget question({
    int? selected,
    ValueChanged<int>? onSelected,
    VoidCallback? onSkip,
    VoidCallback? onHelp,
    EffortRest? rest,
  }) => EffortQuestion(
    question: rest == null ? 'How hard was it?' : 'How hard was set 3?',
    values: rest == null ? 'Set 1 done · 82.5 kg × 8' : '82.5 kg × 8',
    options: byFeel,
    selected: selected,
    onSelected: onSelected ?? (_) {},
    onSkip: onSkip ?? () {},
    onHelp: onHelp ?? () {},
    rest: rest,
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
        isButton: true,
        hasTapAction: true,
        label: 'Moderate\n2–3 reps left',
      ),
    );
    semantics.dispose();
  });

  testWidgets('Skip and the help call back', (tester) async {
    var skipped = 0;
    var helped = 0;
    await pumpComponent(
      tester,
      question(onSkip: () => skipped++, onHelp: () => helped++),
    );

    await tester.tap(find.text('Skip'));
    await tester.tap(find.bySemanticsLabel('Explain'));
    expect((skipped, helped), (1, 1));
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

  testWidgets('with a rest its line sits on top with +15 s and Skip', (
    tester,
  ) async {
    var added = 0;
    var skippedRest = 0;
    var skipped = 0;
    await pumpComponent(
      tester,
      question(
        onSkip: () => skipped++,
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
    await tester.tap(find.text('Skip').first);
    await tester.tap(find.text('Skip').last);
    expect((added, skippedRest, skipped), (1, 1, 1));
  });
}
