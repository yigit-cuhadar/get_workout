import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/core/widgets/muscle_heat.dart';
import 'package:get_workout/core/widgets/program_volume_card.dart';
import 'package:get_workout/core/widgets/volume_band.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import 'component_harness.dart';

void main() {
  late Model3D body;

  setUpAll(() async {
    body = await Model3D.fromGlb(
      File('assets/models/body_male.glb').readAsBytesSync(),
    );
  });

  var taps = 0;

  Future<void> show(WidgetTester tester) => pumpComponent(
    tester,
    ProgramVolumeCard(
      model: body,
      sets: const {
        Muscle.pec: 14,
        Muscle.lat: 12,
        Muscle.frontDelt: 22,
        Muscle.triceps: 12,
        Muscle.biceps: 6,
        Muscle.calf: 0,
      },
      total: 96,
      onTap: () => taps++,
    ),
  );

  testWidgets('the title and the total in sets', (tester) async {
    await show(tester);

    expect(find.text('Weekly sets in this program'), findsOneWidget);
    expect(find.text('96 sets'), findsOneWidget);
  });

  testWidgets('the three busiest muscles as bands, ties in order', (
    tester,
  ) async {
    await show(tester);

    final bands = tester.widgetList<VolumeBand>(find.byType(VolumeBand));
    expect(
      [for (final band in bands) band.muscle],
      [Muscle.frontDelt, Muscle.pec, Muscle.lat],
    );
    expect({for (final band in bands) band.scale}, {25});
  });

  testWidgets('front and back painted by sets', (tester) async {
    await show(tester);

    expect(
      tester.widget<MuscleHeatPair>(find.byType(MuscleHeatPair)).sets,
      containsPair(Muscle.frontDelt, 22),
    );
  });

  testWidgets('a tap opens the full list', (tester) async {
    taps = 0;
    await show(tester);

    await tester.tap(find.text('Weekly sets in this program'));

    expect(taps, 1);
  });
}
