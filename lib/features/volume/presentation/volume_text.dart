import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/weekly_volume.dart';

extension VolumeText on AppLocalizations {
  /// `12 sets`, `12.5 sets`, `1 set`.
  String setsText(double sets) =>
      volumeSets(sets, NumberFormat.decimalPattern(localeName).format(sets));

  String zoneLabel(VolumeZone zone) => switch (zone) {
    VolumeZone.below => volumeBelow(VolumeBand.min),
    VolumeZone.within => volumeWithin(VolumeBand.min, VolumeBand.max),
    VolumeZone.above => volumeAbove(VolumeBand.max),
  };
}

/// The colour of each [VolumeZone], from the theme.
extension VolumeZoneColor on VolumeZone {
  Color color(ColorScheme colors) => switch (this) {
    VolumeZone.below => colors.tertiary,
    VolumeZone.within => colors.primary,
    VolumeZone.above => colors.error,
  };
}
