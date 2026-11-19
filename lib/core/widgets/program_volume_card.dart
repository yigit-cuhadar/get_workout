import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../features/exercises/domain/vocabulary.dart';
import '../../features/volume/presentation/volume_charts.dart';
import '../../features/volume/presentation/volume_text.dart';
import '../../l10n/app_localizations.dart';
import 'volume_band.dart';

/// How a program spreads its weekly [sets] per muscle: the busiest muscles
/// (ties in vocabulary order) as full-width VolumeBands, under the title
/// and the program's [total] sets and a chevron. A tap opens the full list,
/// with the body model, through [onTap].
class ProgramVolumeCard extends StatelessWidget {
  const ProgramVolumeCard({
    super.key,
    required this.sets,
    required this.total,
    required this.onTap,
  });

  final Map<Muscle, double> sets;

  /// The working sets of a week of the program, each once.
  final int total;
  final VoidCallback onTap;

  /// The busiest muscles shown.
  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final scale = volumeScale(sets.values);
    final busiest =
        [
          for (final entry in sets.entries)
            if (entry.value > 0) entry,
        ]..sort((a, b) {
          final bySets = b.value.compareTo(a.value);
          return bySets != 0 ? bySets : a.key.index.compareTo(b.key.index);
        });
    return Material(
      color: style.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.radii.lg),
        side: style.cardBorder == 0
            ? BorderSide.none
            : BorderSide(color: style.colors.line, width: style.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.sm,
            children: [
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: Text(
                      l10n.programVolumeTitle,
                      style: text.titleMedium,
                    ),
                  ),
                  Text(
                    l10n.setsText(total.toDouble()),
                    style: style.data.copyWith(color: style.colors.inkMuted),
                  ),
                  ForgeIcon(
                    ForgeIcons.chevronRight,
                    size: 18,
                    color: style.colors.inkMuted,
                  ),
                ],
              ),
              for (final MapEntry(key: muscle, value: count) in busiest.take(
                _shown,
              ))
                VolumeBand(muscle: muscle, sets: count, scale: scale),
            ],
          ),
        ),
      ),
    );
  }
}
