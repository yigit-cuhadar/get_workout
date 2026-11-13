import '../../programs/domain/calendar_date.dart';
import '../../strength/domain/strength.dart';
import '../../profile/domain/user_profile.dart';
import 'body_entry.dart';
import 'entry_body_fat.dart';

/// One logged weight.
typedef WeightPoint = ({DateTime date, double kg});

/// The weights of [entries] (newest first) in [range] (see
/// [StrengthRange.start]), oldest first.
List<WeightPoint> weightSeries(
  List<BodyEntry> entries, {
  required StrengthRange range,
  required DateTime now,
}) {
  final start = range.start(now);
  return [
    for (final entry in entries.reversed)
      if (entry.weightKg case final kg?)
        if (start == null || !entry.date.isBefore(start))
          (date: entry.date, kg: kg),
  ];
}

/// Whether any of [entries] is from before [range] starts: results a free
/// user is told exist, behind Premium.
bool hasEntryBefore(
  List<BodyEntry> entries, {
  required StrengthRange range,
  required DateTime now,
}) {
  final start = range.start(now);
  return start != null && entries.any((entry) => entry.date.isBefore(start));
}

/// The body fat of each of [entries] it can be estimated for, by entry id;
/// see [entryBodyFat].
Map<String, double> bodyFatByEntry(
  List<BodyEntry> entries, {
  required Sex? sex,
  required double? heightCm,
}) => {
  for (final entry in entries)
    entry.id: ?entryBodyFat(
      entry.measurements,
      sex: sex,
      heightCm: heightCm,
    ).percent,
};

/// The local dates of [entries] that are measurement days, not quick
/// weight logs; for the measurement reminders.
Set<CalendarDate> measuredDates(List<BodyEntry> entries) => {
  for (final entry in entries)
    if (!entry.isWeightOnly) CalendarDate.of(entry.date.toLocal()),
};

/// The newest of [entries] (newest first) that has a weight.
BodyEntry? latestWeighIn(List<BodyEntry> entries) =>
    entries.where((entry) => entry.weightKg != null).firstOrNull;

/// The newest weight of [entries] (newest first).
double? latestWeightKg(List<BodyEntry> entries) =>
    latestWeighIn(entries)?.weightKg;

/// For each pose, the path of the newest photo of [entries] (newest first)
/// taken before [date] by an entry other than [excludeId]: the ghost a new
/// photo of that pose is lined up with.
Map<PhotoPose, String> previousPhotos(
  List<BodyEntry> entries, {
  required DateTime date,
  String? excludeId,
}) {
  final found = <PhotoPose, String>{};
  for (final entry in entries) {
    if (entry.id == excludeId || !entry.date.isBefore(date)) continue;
    for (final MapEntry(:key, :value) in entry.photos.entries) {
      found.putIfAbsent(key, () => value);
    }
    if (found.length == PhotoPose.values.length) break;
  }
  return found;
}
