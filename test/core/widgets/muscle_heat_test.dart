import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/muscle_heat.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import '../../component_harness.dart';

void main() {
  final c = AppPreset.shipped.light;

  test('the scale runs heat-low to heat-high at the band top', () {
    expect(muscleHeatColor(c, 0), c.heatLow);
    expect(muscleHeatColor(c, 10), Color.lerp(c.heatLow, c.heatHigh, 0.5));
    expect(muscleHeatColor(c, 20), c.heatHigh);
  });

  test('over the band the model stays heat-high, never band-over', () {
    expect(muscleHeatColor(c, 26), c.heatHigh);
    expect(muscleHeatColor(c, 26), isNot(c.bandOver));
  });

  test('untrained muscles stay neutral', () {
    expect(muscleHeatColors(c, {Muscle.pec: 14, Muscle.biceps: 0}).keys, [
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
      expect(viewer.partColors['pec_left'], muscleHeatColor(c, 14));
    }
  });

  testWidgets('a muscle over 20 is full heat-high with no outline', (
    tester,
  ) async {
    final body = await tester.runAsync(
      () => Model3D.fromGlb(
        File('assets/models/body_male.glb').readAsBytesSync(),
      ),
    );
    await pumpComponent(
      tester,
      MuscleHeatPair(
        model: body!,
        sets: const {Muscle.pec: 14, Muscle.frontDelt: 22},
      ),
    );

    for (final viewer in tester.widgetList<ModelViewer>(
      find.byType(ModelViewer),
    )) {
      expect(viewer.partColors['front_delt_left'], c.heatHigh);
      expect(viewer.outlinedParts, isEmpty);
    }
  });

  testWidgets('the legend labels the band numbers', (tester) async {
    await pumpComponent(tester, const MuscleHeatLegend());

    for (final text in ['0', '10', '20 sets']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.textContaining('outline'), findsNothing);
  });
}
