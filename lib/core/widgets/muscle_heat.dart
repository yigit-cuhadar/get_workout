import 'package:flutter/material.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../features/exercises/domain/vocabulary.dart';
import '../../l10n/app_localizations.dart';
import 'muscle_model.dart';

/// The weekly sets at which the ramp reaches full accent.
const int muscleHeatFull = 20;

/// Share of accent in the ramp's faint end.
const double _faint = 0.15;

/// A muscle's colour for its weekly [sets]: one accent ramp mixed into
/// surface, from a faint tint toward 0 to full accent at
/// [muscleHeatFull] and over.
Color muscleHeatColor(ForgePalette p, num sets) => Color.lerp(
  p.surface,
  p.accent,
  _faint + (1 - _faint) * (sets / muscleHeatFull).clamp(0, 1),
)!;

/// The ramp's colour for each trained muscle of [sets]; untrained ones are
/// left out and stay neutral.
Map<Muscle, Color> muscleHeatColors(ForgePalette p, Map<Muscle, num> sets) => {
  for (final MapEntry(key: muscle, value: count) in sets.entries)
    if (count > 0) muscle: muscleHeatColor(p, count),
};

/// Small front and back models painted by weekly [sets], side by side.
class MuscleHeatPair extends StatelessWidget {
  const MuscleHeatPair({super.key, required this.model, required this.sets});

  final Model3D model;
  final Map<Muscle, num> sets;

  static const double _width = 44;
  static const double _height = 85;

  @override
  Widget build(BuildContext context) {
    final p = ForgeStyle.of(context).colors;
    final colors = muscleMeshColors(muscleHeatColors(p, sets));
    final base = Color.lerp(p.surface, p.lineStrong, 0.35)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        for (final back in [false, true])
          SizedBox(
            width: _width,
            height: _height,
            child: StillMuscleModel(
              model: model,
              back: back,
              base: base,
              colors: colors,
            ),
          ),
      ],
    );
  }
}

/// The ramp as a bar from 0 to 20 sets, with what the outline marks.
class MuscleHeatLegend extends StatelessWidget {
  const MuscleHeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final l10n = AppLocalizations.of(context);
    final label = style.data.copyWith(fontSize: 11, color: p.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.xs,
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(colors: [muscleHeatColor(p, 0), p.accent]),
          ),
        ),
        SizedBox(
          height: 14,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('0', style: label),
              ),
              Align(child: Text('${muscleHeatFull ~/ 2}', style: label)),
              Align(
                alignment: Alignment.centerRight,
                child: Text(l10n.muscleHeatFull(muscleHeatFull), style: label),
              ),
            ],
          ),
        ),
        Text(
          l10n.muscleHeatOutline(muscleHeatFull),
          style: Theme.of(context).textTheme.labelSmall!
              .copyWith(fontWeight: FontWeight.w400, color: p.inkMuted),
        ),
      ],
    );
  }
}
