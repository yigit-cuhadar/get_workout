import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/plate_calculator.dart';

import '../../component_harness.dart';

void main() {
  const plates = [
    PlateStack(kg: 25, weight: '25 kg', short: '25', count: 2),
    PlateStack(kg: 10, weight: '10 kg', short: '10', count: 1),
    PlateStack(kg: 1.25, weight: '1.25 kg', short: '1.25', count: 1),
  ];

  testWidgets('target, bar, the drawing and the plates per side', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const PlateCalculator(
        target: '142.5 kg',
        bar: '20 kg',
        plates: plates,
        perSide: '61.25 kg',
      ),
    );

    for (final text in [
      '142.5 kg',
      '20 kg',
      'Each side, heaviest first',
      '25 kg',
      '× 2',
      '61.25 kg',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(
      find.descendant(
        of: find.byType(PlateCalculator),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });

  testWidgets('a target the plates cannot make shows the closest', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const PlateCalculator.closest(
        target: '63.7 kg',
        closest: '62.5 kg',
        plates: [
          PlateStack(kg: 20, weight: '20 kg', short: '20', count: 1),
          PlateStack(kg: 1.25, weight: '1.25 kg', short: '1.25', count: 1),
        ],
      ),
    );

    expect(find.text('Closest'), findsOneWidget);
    expect(find.text('62.5 kg'), findsOneWidget);
    expect(
      find.textContaining("Your plates can't make 63.7 kg"),
      findsOneWidget,
    );
  });

  testWidgets('the compact box lists each plate as a tag', (tester) async {
    await pumpComponent(
      tester,
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

    expect(find.text('82.5 kg · each side 31.25'), findsOneWidget);
    expect(find.byType(ForgeTag), findsNWidgets(3));
    expect(find.text('on a 20 kg bar'), findsOneWidget);
  });

  testWidgets('plates differ by size and tone, heaviest widest', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const PlateCalculator(
        target: '142.5 kg',
        bar: '20 kg',
        plates: plates,
        perSide: '61.25 kg',
      ),
    );

    double swatchWidth(String weight) => tester
        .getSize(
          find.descendant(
            of: find.ancestor(
              of: find.text(weight),
              matching: find.byType(Row),
            ),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxHeight == 22,
            ),
          ),
        )
        .width;
    expect(swatchWidth('25 kg'), greaterThan(swatchWidth('10 kg')));
    expect(swatchWidth('10 kg'), greaterThan(swatchWidth('1.25 kg')));
  });
}
