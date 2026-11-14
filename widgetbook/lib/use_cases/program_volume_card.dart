import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/program_volume_card.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final Future<Model3D> _body = rootBundle
    .load('packages/get_workout/assets/models/body_male.glb')
    .then((data) => Model3D.fromGlb(data.buffer.asUint8List()));

@widgetbook.UseCase(name: "A program's weekly sets", type: ProgramVolumeCard)
Widget programVolumeCard(BuildContext context) {
  final shoulders = context.knobs.double.slider(
    label: 'Shoulder sets',
    initialValue: 22,
    max: 30,
    divisions: 60,
  );
  return Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: FutureBuilder(
      future: _body,
      builder: (context, snapshot) => switch (snapshot.data) {
        final model? => ProgramVolumeCard(
          model: model,
          sets: {
            Muscle.frontDelt: shoulders,
            Muscle.pec: 14,
            Muscle.lat: 12,
            Muscle.triceps: 10,
            Muscle.biceps: 6,
          },
          total: 96,
          onTap: () {},
        ),
        null => const SizedBox.shrink(),
      },
    ),
  );
}
