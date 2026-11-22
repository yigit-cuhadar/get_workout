import 'package:material_ui/material_ui.dart';
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
        rows: [
          CalculatorRow('Lose 0.5 kg a week', '2,170'),
          CalculatorRow('Keep weight', '2,720'),
        ],
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
        note: 'Add your height and activity to see the result.',
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(
      find.text('Add your height and activity to see the result.'),
      findsOneWidget,
    );
  });

  testWidgets('a row note under its label and a note under the card', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const CalculatorResult(
        caption: 'Daily energy need',
        value: '1,590 kcal',
        rows: [
          CalculatorRow(
            'Lose 0.5 kg a week',
            '1,500',
            note: 'Raised to the 1,500 kcal daily minimum',
          ),
        ],
        note: 'Fat-free mass index: lean mass divided by height squared.',
      ),
    );

    expect(find.text('Raised to the 1,500 kcal daily minimum'), findsOneWidget);
    expect(
      find.text('Fat-free mass index: lean mass divided by height squared.'),
      findsOneWidget,
    );
  });
}
