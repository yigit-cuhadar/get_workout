import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';

import '../../../../component_harness.dart';

void main() {
  testWidgets('counts down with what comes next, +15 s and Skip rest', (
    tester,
  ) async {
    var added = 0;
    var skipped = 0;
    await pumpComponent(
      tester,
      RestPanel(
        time: '1:12',
        progress: 0.6,
        next: 'Next: Bench Press · set 4 of 4',
        onAddTime: () => added++,
        onSkip: () => skipped++,
      ),
    );

    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('Next: Bench Press · set 4 of 4'), findsOneWidget);
    expect(find.text('1:12'), findsOneWidget);
    final track = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byType(RestTrack),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(track.widthFactor, 0.6);

    await tester.tap(find.text('+15 s'));
    await tester.tap(find.text('Skip rest'));
    expect((added, skipped), (1, 1));
  });

  testWidgets('once over, 0:00 in accent on a full line and no buttons', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const RestPanel.over(time: '0:00', next: 'All sets done'),
    );

    expect(find.text('Rest over'), findsOneWidget);
    expect(find.text('All sets done'), findsOneWidget);
    final time = tester.widget<Text>(find.text('0:00'));
    final context = tester.element(find.text('0:00'));
    expect(time.style!.color, ForgeStyle.of(context).colors.accent);
    expect(find.byType(ForgeButton), findsNothing);
    final track = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(track.widthFactor, 1);
  });
}
