import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/plate_calculator.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(Widget child) =>
    ListView(padding: const EdgeInsets.all(Gap.md), children: [child]);

@widgetbook.UseCase(name: 'Plates', type: PlateCalculator)
Widget platesPlateCalculator(BuildContext context) => _page(
  const PlateCalculator(
    target: '142.5 kg',
    bar: '20 kg',
    plates: [
      PlateStack(kg: 25, weight: '25 kg', short: '25', count: 2),
      PlateStack(kg: 10, weight: '10 kg', short: '10', count: 1),
      PlateStack(kg: 1.25, weight: '1.25 kg', short: '1.25', count: 1),
    ],
    perSide: '61.25 kg',
  ),
);

@widgetbook.UseCase(name: "Can't make the target", type: PlateCalculator)
Widget closestPlateCalculator(BuildContext context) => _page(
  const PlateCalculator.closest(
    target: '63.7 kg',
    closest: '62.5 kg',
    plates: [
      PlateStack(kg: 20, weight: '20 kg', short: '20', count: 1),
      PlateStack(kg: 1.25, weight: '1.25 kg', short: '1.25', count: 1),
    ],
  ),
);

@widgetbook.UseCase(name: 'Compact', type: PlateCalculator)
Widget compactPlateCalculator(BuildContext context) => _page(
  const PlateCalculator.compact(
    target: '82.5 kg',
    bar: '20 kg',
    perSide: '31.25',
    plates: [
      PlateStack(kg: 25, weight: '25 kg', short: '25', count: 1),
      PlateStack(kg: 5, weight: '5 kg', short: '5', count: 1),
      PlateStack(kg: 1.25, weight: '1.25 kg', short: '1.25', count: 1),
    ],
  ),
);
