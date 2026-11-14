import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/workout/presentation/widgets/progression_hint.dart';

void main() {
  testWidgets('a tap takes the suggested load', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.slate.lightTheme(),
        home: Scaffold(
          body: ProgressionHint(
            text: 'You hit 8 reps last time. Try 82.5 kg.',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('You hit 8 reps last time. Try 82.5 kg.'));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(ProgressionHint)).height,
      greaterThanOrEqualTo(44),
    );
  });
}
