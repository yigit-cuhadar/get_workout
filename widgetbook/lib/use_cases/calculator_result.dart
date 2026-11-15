import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/calculators/presentation/widgets/calculator_result.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(Widget child) =>
    ListView(padding: const EdgeInsets.all(Gap.md), children: [child]);

@widgetbook.UseCase(name: 'Result by goal', type: CalculatorResult)
Widget resultCalculatorResult(BuildContext context) => _page(
  CalculatorResult(
    caption: 'Daily energy need',
    value: context.knobs.string(label: 'Value', initialValue: '2,720 kcal'),
    rows: const [
      ('Lose 0.5 kg a week', '2,170'),
      ('Keep weight', '2,720'),
      ('Gain 0.25 kg a week', '2,995'),
    ],
  ),
);

@widgetbook.UseCase(name: 'Missing input', type: CalculatorResult)
Widget missingCalculatorResult(BuildContext context) => _page(
  const CalculatorResult.missing(
    caption: 'Daily energy need',
    message: 'Add your height and activity to see the result.',
  ),
);
