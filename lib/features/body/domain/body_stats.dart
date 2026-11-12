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

/// Whether [entries] have a weight from before [range] starts: weights a
/// free user is told exist, behind Premium.
bool hasWeightBefore(
  List<BodyEntry> entries, {
  required StrengthRange range,
  required DateTime now,
}) {
  final start = range.start(now);
  return start != null &&
      entries.any(
        (entry) => entry.weightKg != null && entry.date.isBefore(start),
      );
}

/// One entry's body fat.
typedef BodyFatPoint = ({DateTime date, double percent});

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

/// The body fat [percents] (see [bodyFatByEntry]) of [entries] (newest
/// first) in [range], oldest first.
List<BodyFatPoint> bodyFatSeries(
  List<BodyEntry> entries,
  Map<String, double> percents, {
  required StrengthRange range,
  required DateTime now,
}) {
  final start = range.start(now);
  return [
    for (final entry in entries.reversed)
      if (percents[entry.id] case final percent?)
        if (start == null || !entry.date.isBefore(start))
          (date: entry.date, percent: percent),
  ];
}

/// Whether any of [entries] with a body fat in [percents] is from before
/// [range] starts; see [hasWeightBefore].
bool hasBodyFatBefore(
  List<BodyEntry> entries,
  Map<String, double> percents, {
  required StrengthRange range,
  required DateTime now,
}) {
  final start = range.start(now);
  return start != null &&
      entries.any(
        (entry) => percents.containsKey(entry.id) && entry.date.isBefore(start),
      );
}

/// The local dates of [entries] that are measurement days, not quick
/// weight logs; for the measurement reminders.
Set<CalendarDate> measuredDates(List<BodyEntry> entries) => {
  for (final entry in entries)
    if (!entry.isWeightOnly) CalendarDate.of(entry.date.toLocal()),
};

/// The newest weight of [entries] (newest first).
double? latestWeightKg(List<BodyEntry> entries) {
  for (final entry in entries) {
    if (entry.weightKg case final kg?) return kg;
  }
  return null;
}

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
