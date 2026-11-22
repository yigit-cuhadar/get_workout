import 'package:material_ui/material_ui.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../app/theme.dart';
import '../../features/exercises/domain/vocabulary.dart';
import '../../features/volume/domain/weekly_volume.dart';
import '../../l10n/app_localizations.dart';
import 'muscle_model.dart';

/// A muscle's colour for its weekly [sets] on the heat scale, which shares
/// the volume band's numbers: heat-low toward 0 to heat-high at
/// [VolumeRange.max]. Over the band it stays heat-high; only the bars mark
/// it.
Color muscleHeatColor(GwColors c, num sets) =>
    Color.lerp(c.heatLow, c.heatHigh, (sets / VolumeRange.max).clamp(0, 1))!;

/// The scale's colour for each trained muscle of [sets]; untrained ones are
/// left out and stay neutral.
Map<Muscle, Color> muscleHeatColors(GwColors c, Map<Muscle, num> sets) => {
  for (final MapEntry(key: muscle, value: count) in sets.entries)
    if (count > 0) muscle: muscleHeatColor(c, count),
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
    final colors = muscleMeshColors(
      muscleHeatColors(GwColors.of(context), sets),
    );
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

/// The scale as a bar from 0 sets (the body's colour) to
/// [VolumeRange.max], labelled at 0, [VolumeRange.min] and
/// [VolumeRange.max].
class MuscleHeatLegend extends StatelessWidget {
  const MuscleHeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final heat = GwColors.of(context);
    final l10n = AppLocalizations.of(context);
    final label = style.data.copyWith(fontSize: 11, color: p.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.xs,
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [muscleModelBase(p), heat.heatLow, heat.heatHigh],
              stops: const [0, 1 / VolumeRange.max, 1],
            ),
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
              Align(
                alignment: const Alignment(
                  2 * VolumeRange.min / VolumeRange.max - 1,
                  0,
                ),
                child: Text('${VolumeRange.min}', style: label),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(l10n.muscleHeatFull(VolumeRange.max), style: label),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A card of what a workout worked: [MuscleHeatPair] painted by its [sets],
/// beside a [title] and a [line] naming the busiest muscles. Without a
/// [model] (loading, or it could not load) the figures are shimmering
/// bars.
class WorkedMuscles extends StatelessWidget {
  const WorkedMuscles({
    super.key,
    required this.model,
    required this.sets,
    required this.title,
    required this.line,
  });

  final Model3D? model;
  final Map<Muscle, num> sets;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final model = this.model;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, Gap.md),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: p.line, width: style.cardBorder),
      ),
      child: Row(
        spacing: 14,
        children: [
          ExcludeSemantics(
            child: model == null
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 12,
                    children: [
                      SkeletonBar(
                        width: MuscleHeatPair._width,
                        height: MuscleHeatPair._height,
                      ),
                      SkeletonBar(
                        width: MuscleHeatPair._width,
                        height: MuscleHeatPair._height,
                      ),
                    ],
                  )
                : MuscleHeatPair(model: model, sets: sets),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.xs,
              children: [
                Text(
                  title,
                  style: text.bodySmall!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                Text(line, style: text.bodySmall!.copyWith(color: p.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
