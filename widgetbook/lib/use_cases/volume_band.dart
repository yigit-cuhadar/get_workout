import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/volume_band.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

/// The card's scale: 25 sets fill the track.
const _scale = 25.0;

@widgetbook.UseCase(name: 'Below, in and above the band', type: VolumeBand)
Widget volumeBands(BuildContext context) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      VolumeBand(
        muscle: Muscle.pec,
        sets: context.knobs.double.slider(
          label: 'Chest sets',
          initialValue: 14,
          max: _scale,
          divisions: 50,
        ),
        scale: _scale,
      ),
      const VolumeBand(muscle: Muscle.frontDelt, sets: 22, scale: _scale),
      const VolumeBand(muscle: Muscle.hamstring, sets: 8, scale: _scale),
      const VolumeBand(muscle: Muscle.calf, sets: 0, scale: _scale),
    ],
  ),
);
