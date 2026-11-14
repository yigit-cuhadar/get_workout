import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/plate_calculator.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

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

  test('each kilo plate has its own size, heaviest biggest', () {
    expect(
      [for (final look in PlateLook.values) (look.kg, look.width, look.height)],
      [
        (25, 16, 120),
        (20, 16, 108),
        (15, 14, 96),
        (10, 12, 84),
        (5, 10, 68),
        (2.5, 8, 56),
        (1.25, 6, 44),
      ],
    );
    for (final look in PlateLook.values) {
      expect(PlateLook.of(look.kg), look);
    }
  });

  test('a pound plate is drawn as its kilo match', () {
    final looks = {
      for (final lb in const <double>[55, 45, 35, 25, 10, 5, 2.5])
        lb: PlateLook.of(WeightUnit.lb.toKg(lb)),
    };
    expect(looks, {
      55: PlateLook.kg25,
      45: PlateLook.kg20,
      35: PlateLook.kg15,
      25: PlateLook.kg10,
      10: PlateLook.kg5,
      5: PlateLook.kg2p5,
      2.5: PlateLook.kg1p25,
    });
  });

  test('any other plate is drawn as the nearest, halfway as the heavier', () {
    expect(PlateLook.of(50), PlateLook.kg25);
    expect(PlateLook.of(0.5), PlateLook.kg1p25);
    expect(PlateLook.of(4), PlateLook.kg5);
    expect(PlateLook.of(7.5), PlateLook.kg10);
    expect(PlateLook.of(17.5), PlateLook.kg20);
  });

  test('every preset colours the plates alike in each brightness', () {
    List<Color> plates(GwColors c) => [
      c.plate25,
      c.plate20,
      c.plate15,
      c.plate10,
      c.plate5,
      c.plate2p5,
      c.plate1p25,
    ];
    for (final preset in AppPreset.values) {
      expect(plates(preset.light), const [
        Color(0xFFA6473C),
        Color(0xFF3B5A93),
        Color(0xFFB8963E),
        Color(0xFF3F7D62),
        Color(0xFFD9DCE1),
        Color(0xFFA6473C),
        Color(0xFF8B94A3),
      ]);
      expect(plates(preset.dark), const [
        Color(0xFFE0907F),
        Color(0xFF9DB0D6),
        Color(0xFFD8BD72),
        Color(0xFF79B597),
        Color(0xFFEEF1F5),
        Color(0xFFE0907F),
        Color(0xFF6B7689),
      ]);
    }
  });

  testWidgets('a plate row swatch takes its plate colour', (tester) async {
    await pumpComponent(
      tester,
      const PlateCalculator(
        target: '80 kg',
        bar: '20 kg',
        plates: [
          PlateStack(kg: 25, weight: '25 kg', short: '25', count: 1),
          PlateStack(kg: 5, weight: '5 kg', short: '5', count: 1),
        ],
        perSide: '30 kg',
      ),
    );

    final colors = AppPreset.shipped.light;
    BoxDecoration swatch(String weight) =>
        tester
                .widget<Container>(
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
                .decoration!
            as BoxDecoration;
    expect(swatch('25 kg').color, colors.plate25);
    expect(swatch('25 kg').border, isNull);
    // The white plate keeps a line-strong edge.
    final lineStrong = ForgeStyle.of(tester.element(find.text('5 kg')))
        .colors
        .lineStrong;
    expect(swatch('5 kg').color, colors.plate5);
    expect((swatch('5 kg').border! as Border).top.color, lineStrong);
  });

  testWidgets('plates differ by size, heaviest widest', (tester) async {
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
