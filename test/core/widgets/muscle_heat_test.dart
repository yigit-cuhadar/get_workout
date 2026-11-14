import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/muscle_heat.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:forge_ui/forge_ui.dart';

import 'component_harness.dart';

void main() {
  final p = AppPreset.shipped.lightTheme().extension<ForgeStyle>()!.colors;

  test('one accent ramp from a faint tint to full accent at 20', () {
    expect(muscleHeatColor(p, 0), Color.lerp(p.surface, p.accent, 0.15));
    expect(muscleHeatColor(p, 10), Color.lerp(p.surface, p.accent, 0.575));
    expect(muscleHeatColor(p, 20), p.accent);
    expect(muscleHeatColor(p, 26), p.accent);
  });

  test('untrained muscles stay neutral', () {
    expect(muscleHeatColors(p, {Muscle.pec: 14, Muscle.biceps: 0}).keys, [
      Muscle.pec,
    ]);
  });

  testWidgets('the pair paints front and back by sets', (tester) async {
    final body = await tester.runAsync(
      () => Model3D.fromGlb(
        File('assets/models/body_male.glb').readAsBytesSync(),
      ),
    );
    await pumpComponent(
      tester,
      MuscleHeatPair(model: body!, sets: const {Muscle.pec: 14}),
    );

    final viewers = tester.widgetList<ModelViewer>(find.byType(ModelViewer));
    expect(viewers, hasLength(2));
    for (final viewer in viewers) {
      expect(viewer.partColors['pec_left'], muscleHeatColor(p, 14));
    }
  });

  testWidgets('the legend labels the ramp', (tester) async {
    await pumpComponent(tester, const MuscleHeatLegend());

    for (final text in ['0', '10', '20 sets']) {
      expect(find.text(text), findsOneWidget);
    }
  });
}
