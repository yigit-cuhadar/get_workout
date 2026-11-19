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

/// The weigh-in a new log is compared with and its ruler starts at: the
/// newest of [entries] (newest first) with a weight, or, for an [edited]
/// entry, the newest one before it.
BodyEntry? previousWeighIn(List<BodyEntry> entries, {BodyEntry? edited}) =>
    latestWeighIn([
      for (final entry in entries)
        if (edited == null ||
            (entry.id != edited.id && entry.date.isBefore(edited.date)))
          entry,
    ]);

/// Where a weight ruler starts without a weight of its own (LW05): the
/// [previous] weigh-in, else the profile's [profileKg], else a common
/// adult weight.
double startWeightKg({BodyEntry? previous, double? profileKg}) =>
    previous?.weightKg ?? profileKg ?? defaultStartWeightKg;

/// The ruler's start with neither a weigh-in nor a profile weight.
const defaultStartWeightKg = 70.0;

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

/// Which way a change in an Overview box went for the user.
enum ChangeTone { good, bad, neutral }

/// One Overview box: its latest [value] and the [change] since the
/// measurement day before the newest one; null when either side is
/// missing.
typedef OverviewBox = ({double value, double? change, ChangeTone tone});

/// The Overview's three boxes, each null without a value: the latest
/// weigh-in's weight, the newest body fat, and the lean mass the latest
/// weight holds at that body fat.
typedef BodyOverview = ({
  OverviewBox? weight,
  OverviewBox? bodyFat,
  OverviewBox? leanMass,
});

/// The Overview boxes of [entries] (newest first), [bodyFat] by entry id.
/// Changes are against the measurement day before the newest one (the
/// baseline), from values dated after it: weight toward [targetKg] is
/// good (neutral without a target), body fat down and lean mass up are
/// good.
BodyOverview bodyOverview(
  List<BodyEntry> entries,
  Map<String, double> bodyFat, {
  required double? targetKg,
}) {
  final days = [
    for (final entry in entries)
      if (!entry.isWeightOnly) entry,
  ];
  final baseline = days.length > 1 ? days[1] : null;
  final weighIn = latestWeighIn(entries);
  final fatEntry = entries.where((e) => bodyFat.containsKey(e.id)).firstOrNull;
  bool after(BodyEntry? entry) =>
      baseline != null && entry != null && entry.date.isAfter(baseline.date);
  double? lean(double? kg, double? percent) =>
      kg == null || percent == null ? null : kg * (1 - percent / 100);

  ChangeTone tone(double? change, {required bool upIsGood}) {
    if (change == null || change == 0) return ChangeTone.neutral;
    return (change > 0) == upIsGood ? ChangeTone.good : ChangeTone.bad;
  }

  OverviewBox? box(
    double? value,
    double? from,
    bool counts,
    ChangeTone Function(double?) toneOf,
  ) {
    if (value == null) return null;
    final change = counts && from != null ? value - from : null;
    return (value: value, change: change, tone: toneOf(change));
  }

  final kg = weighIn?.weightKg;
  final fat = fatEntry == null ? null : bodyFat[fatEntry.id];
  final baseKg = baseline?.weightKg;
  final baseFat = baseline == null ? null : bodyFat[baseline.id];
  return (
    weight: box(kg, baseKg, after(weighIn), (change) {
      if (targetKg == null || change == null || kg == null) {
        return ChangeTone.neutral;
      }
      final closer = (kg - targetKg).abs() - (kg - change - targetKg).abs();
      return closer == 0
          ? ChangeTone.neutral
          : closer < 0
          ? ChangeTone.good
          : ChangeTone.bad;
    }),
    bodyFat: box(
      fat,
      baseFat,
      after(fatEntry),
      (change) => tone(change, upIsGood: false),
    ),
    leanMass: box(
      lean(kg, fat),
      lean(baseKg, baseFat),
      after(weighIn) && after(fatEntry),
      (change) => tone(change, upIsGood: true),
    ),
  );
}
