import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../app/theme.dart';
import '../../features/exercises/domain/vocabulary.dart';
import '../../features/exercises/presentation/vocabulary_labels.dart';
import '../../features/volume/domain/weekly_volume.dart';
import '../../features/volume/presentation/volume_text.dart';
import '../../l10n/app_localizations.dart';

/// A [muscle]'s weekly [sets] as a Forge BandBar on a track up to
/// [scale] sets, ticked at the [VolumeRange] ends: below it in
/// band-below, in it in band-in, above it in band-over; none muted.
class VolumeBand extends StatelessWidget {
  const VolumeBand({
    super.key,
    required this.muscle,
    required this.sets,
    required this.scale,
  });

  final Muscle muscle;
  final double sets;

  /// The sets the full track stands for; bars of one list share it
  /// (`volumeScale`).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final band = GwColors.of(context);
    return BandBar(
      label: l10n.muscleName(muscle),
      valueLabel: l10n.setsText(sets),
      value: sets / scale,
      muted: sets == 0,
      low: VolumeRange.min / scale,
      high: VolumeRange.max / scale,
      fills: BandBarFills(
        below: band.bandBelow,
        within: band.bandIn,
        above: band.bandOver,
      ),
    );
  }
}
