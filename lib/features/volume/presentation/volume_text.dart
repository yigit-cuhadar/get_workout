import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../domain/weekly_volume.dart';

extension VolumeText on AppLocalizations {
  /// `12 sets`, `12.5 sets`, `1 set`.
  String setsText(double sets) =>
      volumeSets(sets, NumberFormat.decimalPattern(localeName).format(sets));

  /// `96` in the locale's digits and grouping.
  String wholeNumber(int value) =>
      NumberFormat.decimalPattern(localeName).format(value);

  String zoneLabel(VolumeZone zone) => switch (zone) {
    VolumeZone.below => volumeBelow(VolumeRange.min),
    VolumeZone.within => volumeWithin(VolumeRange.min, VolumeRange.max),
    VolumeZone.above => volumeAbove(VolumeRange.max),
  };
}

/// The week starting on [start]: "Nov 9–15", or "Oct 26–Nov 1" across two
/// months.
String weekRangeText(BuildContext context, CalendarDate start) {
  final l10n = AppLocalizations.of(context);
  final dates = MaterialLocalizations.of(context);
  final last = start.addDays(DateTime.daysPerWeek - 1);
  return l10n.progressWeekRange(
    dates.formatShortMonthDay(start.toLocalDateTime()),
    start.month == last.month
        ? '${last.day}'
        : dates.formatShortMonthDay(last.toLocalDateTime()),
  );
}
