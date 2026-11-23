import 'package:material_ui/material_ui.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../app/theme.dart';
import '../../features/exercises/domain/vocabulary.dart';
import '../../features/exercises/presentation/vocabulary_labels.dart';
import '../../features/volume/domain/weekly_volume.dart';
import '../../features/volume/presentation/volume_text.dart';
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

/// Front and back models painted by [sets], side by side, each 100px
/// wide.
class MuscleHeatPair extends StatelessWidget {
  const MuscleHeatPair({super.key, required this.model, required this.sets});

  final Model3D model;
  final Map<Muscle, num> sets;

  static const double _width = 100;
  static const double _height = 190;
  static const double _gap = 24;

  @override
  Widget build(BuildContext context) {
    final p = ForgeStyle.of(context).colors;
    final colors = muscleMeshColors(
      muscleHeatColors(GwColors.of(context), sets),
    );
    final base = Color.lerp(p.surface, p.lineStrong, 0.35)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _gap,
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

/// A card of what a workout worked: its [title] over a [MuscleHeatPair]
/// painted by its [sets], then the [shown] busiest muscles as bars, each
/// with its sets and filled in success relative to the busiest. Without a
/// [model] (loading, or it could not load) the figures are shimmering
/// bars.
class WorkedMuscles extends StatelessWidget {
  const WorkedMuscles({
    super.key,
    required this.model,
    required this.sets,
    required this.title,
  });

  final Model3D? model;
  final Map<Muscle, double> sets;
  final String title;

  static const shown = 4;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final model = this.model;
    final busiest = sets.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final most = busiest.isEmpty ? 0.0 : busiest.first.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, Gap.md),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: p.line, width: style.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          Text(title, style: text.titleMedium),
          Center(
            child: ExcludeSemantics(
              child: model == null
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: MuscleHeatPair._gap,
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
          ),
          for (final MapEntry(key: muscle, value: count) in busiest.take(shown))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.xs,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.muscleName(muscle),
                        style: text.bodySmall!.copyWith(color: p.ink),
                      ),
                    ),
                    Text(
                      l10n.setsText(count),
                      style: style.data.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
                Container(
                  height: _bar,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: p.surfaceSunken,
                    borderRadius: BorderRadius.circular(_bar / 2),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: count / most,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.success,
                        borderRadius: BorderRadius.circular(_bar / 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static const double _bar = 6;
}
