import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/volume_band.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import '../../component_harness.dart';

void main() {
  final band = AppPreset.shipped.lightTheme().extension<GwColors>()!;

  Future<BandBar> show(WidgetTester tester, double sets) async {
    await pumpComponent(
      tester,
      VolumeBand(muscle: Muscle.pec, sets: sets, scale: 25),
    );
    return tester.widget<BandBar>(find.byType(BandBar));
  }

  /// The colour the bar is filled with.
  Color fill(WidgetTester tester) =>
      (tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(BandBar),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .last
                  .decoration
              as BoxDecoration)
          .color!;

  testWidgets('names the muscle and its sets', (tester) async {
    await show(tester, 14);

    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('14 sets'), findsOneWidget);
  });

  testWidgets('ticks at 10 and 20 on the scale', (tester) async {
    final bar = await show(tester, 14);

    expect(bar.value, 14 / 25);
    expect(bar.low, 10 / 25);
    expect(bar.high, 20 / 25);
  });

  testWidgets('fills in the band roles, both ends inside', (tester) async {
    for (final (sets, color) in [
      (8.0, band.bandBelow),
      (10.0, band.bandIn),
      (20.0, band.bandIn),
      (22.0, band.bandOver),
    ]) {
      await show(tester, sets);
      expect(fill(tester), color, reason: '$sets sets');
    }
  });
}
