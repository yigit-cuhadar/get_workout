import 'package:material_ui/material_ui.dart';
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
      CalculatorRow('Lose 0.5 kg a week', '2,170'),
      CalculatorRow('Keep weight', '2,720'),
      CalculatorRow('Gain 0.25 kg a week', '2,995'),
    ],
  ),
);

@widgetbook.UseCase(name: 'Missing input', type: CalculatorResult)
Widget missingCalculatorResult(BuildContext context) => _page(
  const CalculatorResult.missing(
    caption: 'Daily energy need',
    note: 'Add your height and activity to see the result.',
  ),
);

@widgetbook.UseCase(name: 'Rows and a note', type: CalculatorResult)
Widget noteCalculatorResult(BuildContext context) => _page(
  const CalculatorResult(
    caption: 'BMI',
    value: '25.4',
    rows: [
      CalculatorRow('FFMI', '20.5'),
      CalculatorRow('FFMI adjusted to 1.8 m', '20.5'),
    ],
    note: 'Fat-free mass index: lean mass divided by height squared (kg/m²).',
  ),
);

@widgetbook.UseCase(name: 'Row note', type: CalculatorResult)
Widget rowNoteCalculatorResult(BuildContext context) => _page(
  const CalculatorResult(
    caption: 'Daily energy need',
    value: '1,590 kcal',
    rows: [
      CalculatorRow(
        'Lose 0.5 kg a week',
        '1,500',
        note: 'Raised to the 1,500 kcal daily minimum',
      ),
      CalculatorRow('Keep weight', '1,590'),
      CalculatorRow('Gain 0.25 kg a week', '1,865'),
    ],
  ),
);
