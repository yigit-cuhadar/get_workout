import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/muscle_heat.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final Future<Model3D> _body = rootBundle
    .load('packages/get_workout/assets/models/body_male.glb')
    .then((data) => Model3D.fromGlb(data.buffer.asUint8List()));

@widgetbook.UseCase(name: 'Front and back by weekly sets', type: MuscleHeatPair)
Widget muscleHeatPair(BuildContext context) {
  final chest = context.knobs.int.slider(
    label: 'Chest sets',
    initialValue: 14,
    max: 30,
  );
  return Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: FutureBuilder(
      future: _body,
      builder: (context, snapshot) => switch (snapshot.data) {
        final model? => MuscleHeatPair(
          model: model,
          sets: {
            Muscle.pec: chest,
            Muscle.frontDelt: 22,
            Muscle.lat: 12,
            Muscle.quads: 12,
            Muscle.biceps: 6,
          },
        ),
        null => const SizedBox.shrink(),
      },
    ),
  );
}

@widgetbook.UseCase(name: 'Ramp legend', type: MuscleHeatLegend)
Widget muscleHeatLegend(BuildContext context) =>
    const Padding(padding: EdgeInsets.all(Gap.md), child: MuscleHeatLegend());
