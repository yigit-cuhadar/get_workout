import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/program_volume_card.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

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
    child: ProgramVolumeCard(
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
  );
}
