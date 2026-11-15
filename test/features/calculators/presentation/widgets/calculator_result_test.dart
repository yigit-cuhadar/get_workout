import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/calculators/presentation/widgets/calculator_result.dart';

import '../../../../component_harness.dart';

void main() {
  testWidgets('the main figure in mono, then a row per goal', (tester) async {
    await pumpComponent(
      tester,
      const CalculatorResult(
        caption: 'Daily energy need',
        value: '2,720 kcal',
        rows: [('Lose 0.5 kg a week', '2,170'), ('Keep weight', '2,720')],
      ),
    );

    final context = tester.element(find.text('2,720 kcal'));
    final figure = tester.widget<Text>(find.text('2,720 kcal'));
    expect(figure.style!.fontFamily, ForgeStyle.of(context).data.fontFamily);
    expect(find.text('Lose 0.5 kg a week'), findsOneWidget);
    expect(find.text('2,170'), findsOneWidget);
  });

  testWidgets('a missing input shows a dash and what to add', (tester) async {
    await pumpComponent(
      tester,
      const CalculatorResult.missing(
        caption: 'Daily energy need',
        message: 'Add your height and activity to see the result.',
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(
      find.text('Add your height and activity to see the result.'),
      findsOneWidget,
    );
  });
}
