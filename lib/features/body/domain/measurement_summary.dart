import 'package:forge_core/forge_core.dart';

import '../../profile/domain/user_profile.dart';
import 'body_entry.dart';
import 'entry_body_fat.dart';

/// Whether [entry] is a measurement day: it has measurements or photos.
/// A quick weight log is not one.
bool isMeasurementDay(BodyEntry entry) => !entry.isWeightOnly;

/// The measurement days [after] can be compared with: those of [entries]
/// (newest first) dated before it, newest first.
List<BodyEntry> baselineCandidates(List<BodyEntry> entries, BodyEntry after) =>
    [
      for (final entry in entries)
        if (entry.id != after.id &&
            isMeasurementDay(entry) &&
            entry.date.isBefore(after.date))
          entry,
    ];

/// The measurement days of [entries] (newest first) that have an earlier
/// one to be compared with, newest first; empty with fewer than two.
List<BodyEntry> comparableDays(List<BodyEntry> entries) => [
  for (final entry in entries)
    if (isMeasurementDay(entry) &&
        baselineCandidates(entries, entry).isNotEmpty)
      entry,
];

/// What an entry is compared with.
sealed class Baseline extends Equatable {
  const Baseline();

  @override
  List<Object?> get props => [];
}

/// The newest earlier measurement day; the default.
final class PreviousDay extends Baseline {
  const PreviousDay();
}

/// The oldest measurement day.
final class FirstDay extends Baseline {
  const FirstDay();
}

/// One earlier measurement day the user picked.
final class ChosenDay extends Baseline {
  const ChosenDay(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

/// The entry another one (`after`) is compared with under a [Baseline]:
/// one of its [baselineCandidates], or null when there is none. A chosen day
/// that is no longer a candidate (deleted, or now dated after it) gives
/// the previous day.
class FindBaseline {
  const FindBaseline();

  BodyEntry? call(List<BodyEntry> entries, BodyEntry after, Baseline baseline) {
    final candidates = baselineCandidates(entries, after);
    if (candidates.isEmpty) return null;
    return switch (baseline) {
      PreviousDay() => candidates.first,
      FirstDay() => candidates.last,
      ChosenDay(:final id) =>
        candidates.where((entry) => entry.id == id).firstOrNull ??
            candidates.first,
    };
  }
}

/// A value on the earlier and the later of two dates.
typedef ValuePair = ({double? before, double? after});

extension ValueChange on ValuePair {
  /// After minus before; null unless both are known.
  double? get change {
    final from = before;
    final to = after;
    return from == null || to == null ? null : to - from;
  }
}

/// One row of measurements: a single one, or both sides of a pair (left
/// first), each with its values.
class MeasurementRow extends Equatable {
  const MeasurementRow(this.measurements, this.values);

  /// A group of [pairedMeasurements].
  final List<BodyMeasurement> measurements;

  /// In cm, one per measurement.
  final List<ValuePair> values;

  @override
  List<Object?> get props => [measurements, values];
}

/// The body fat of the later entry with the fat and lean mass it splits
/// that entry's weight into, each next to the earlier entry's.
class BodyComposition extends Equatable {
  const BodyComposition({
    required this.percent,
    required this.fatKg,
    required this.leanKg,
  });

  final ValuePair percent;

  /// Null, as [leanKg], when the later entry has no weight.
  final ValuePair? fatKg;
  final ValuePair? leanKg;

  @override
  List<Object?> get props => [percent, fatKg, leanKg];
}

/// The way to the profile's target weight from the later entry's weight.
class TargetProgress extends Equatable {
  const TargetProgress({
    required this.targetKg,
    required this.toGoKg,
    this.estimate,
  });

  /// Closer than this counts as reached.
  static const reachedWithinKg = 0.05;

  /// Entries closer together give no rate.
  static const minSpan = Duration(days: 7);

  /// Estimates further out than this are not given.
  static const maxEstimate = Duration(days: 730);

  final double targetKg;

  /// The target minus the weight: positive to gain, negative to lose.
  final double toGoKg;

  /// When the target is reached at the rate between the two entries; null
  /// when that cannot be said.
  final DateTime? estimate;

  bool get reached => toGoKg.abs() < reachedWithinKg;

  /// From [after]'s weight, with an [estimate] at the rate since
  /// [before]'s. No estimate when the target is reached, without an
  /// earlier weight, with less than [minSpan] between the entries, when
  /// the weight did not move toward the target, or when the estimate is
  /// before [now] or more than [maxEstimate] after it. Null without a
  /// target or a later weight.
  static TargetProgress? of({
    required double? targetKg,
    required BodyEntry after,
    required BodyEntry? before,
    required DateTime now,
  }) {
    final weightKg = after.weightKg;
    if (targetKg == null || weightKg == null) return null;
    final toGoKg = targetKg - weightKg;
    final progress = TargetProgress(targetKg: targetKg, toGoKg: toGoKg);
    final startKg = before?.weightKg;
    if (progress.reached || before == null || startKg == null) {
      return progress;
    }
    final span = after.date.difference(before.date);
    final changeKg = weightKg - startKg;
    // Also covers no change at all: its sign is never the target's.
    if (span < minSpan || changeKg.sign != toGoKg.sign) return progress;
    // Checked before making a date of it: a tiny change gives a huge span.
    final ahead = span.inMicroseconds * (toGoKg / changeKg);
    final latest = now.add(maxEstimate).difference(after.date);
    if (ahead > latest.inMicroseconds) return progress;
    final estimate = after.date.add(Duration(microseconds: ahead.round()));
    if (estimate.isBefore(now)) return progress;
    return TargetProgress(
      targetKg: targetKg,
      toGoKg: toGoKg,
      estimate: estimate,
    );
  }

  @override
  List<Object?> get props => [targetKg, toGoKg, estimate];
}

/// One measurement day ([after]) next to an earlier one ([before]), or on
/// its own when there is none. Metric; every number shown is worked out
/// here.
class MeasurementSummary extends Equatable {
  const MeasurementSummary({
    required this.after,
    required this.before,
    required this.bodyFat,
    required this.composition,
    required this.weightKg,
    required this.measurements,
    required this.target,
    required this.poses,
  });

  /// [profile] gives the sex and height for body fat, and the target
  /// weight; [now] bounds the target estimate.
  factory MeasurementSummary.of({
    required BodyEntry after,
    required BodyEntry? before,
    required UserProfile profile,
    required DateTime now,
  }) {
    EntryBodyFat fatOf(BodyEntry entry) => entryBodyFat(
      entry.measurements,
      sex: profile.sex,
      heightCm: profile.heightCm,
    );
    final bodyFat = fatOf(after);
    final keys = {...after.measurements.keys, ...?before?.measurements.keys};
    return MeasurementSummary(
      after: after,
      before: before,
      bodyFat: bodyFat,
      composition: switch (bodyFat.percent) {
        final percent? => _composition(
          after: (percent: percent, kg: after.weightKg),
          before: before == null
              ? null
              : (percent: fatOf(before).percent, kg: before.weightKg),
        ),
        null => null,
      },
      weightKg: after.weightKg == null && before?.weightKg == null
          ? null
          : (before: before?.weightKg, after: after.weightKg),
      measurements: [
        for (final group in pairedMeasurements(keys))
          MeasurementRow(group, [
            for (final measurement in group)
              (
                before: before?.measurements[measurement],
                after: after.measurements[measurement],
              ),
          ]),
      ],
      target: TargetProgress.of(
        targetKg: profile.targetWeightKg,
        after: after,
        before: before,
        now: now,
      ),
      poses: [
        for (final pose in PhotoPose.values)
          if (after.photos.containsKey(pose) ||
              (before?.photos.containsKey(pose) ?? false))
            pose,
      ],
    );
  }

  static BodyComposition _composition({
    required ({double percent, double? kg}) after,
    required ({double? percent, double? kg})? before,
  }) {
    double? fat(double? percent, double? kg) =>
        percent == null || kg == null ? null : kg * percent / 100;
    double? lean(double? percent, double? kg) => switch (fat(percent, kg)) {
      final fatKg? => kg! - fatKg,
      null => null,
    };
    final hasWeight = after.kg != null;
    return BodyComposition(
      percent: (before: before?.percent, after: after.percent),
      fatKg: hasWeight
          ? (
              before: fat(before?.percent, before?.kg),
              after: fat(after.percent, after.kg),
            )
          : null,
      leanKg: hasWeight
          ? (
              before: lean(before?.percent, before?.kg),
              after: lean(after.percent, after.kg),
            )
          : null,
    );
  }

  final BodyEntry after;

  /// Null when there is no earlier measurement day.
  final BodyEntry? before;

  /// [after]'s body fat, or why it has none.
  final EntryBodyFat bodyFat;

  /// Null while [bodyFat] has no percentage.
  final BodyComposition? composition;

  /// Null when neither entry has a weight.
  final ValuePair? weightKg;

  /// Every measurement either entry has, in their usual order.
  final List<MeasurementRow> measurements;

  /// Null without a target weight or a weight on [after].
  final TargetProgress? target;

  /// The poses either entry has a photo of, in their usual order.
  final List<PhotoPose> poses;

  @override
  List<Object?> get props => [
    after,
    before,
    bodyFat,
    composition,
    weightKg,
    measurements,
    target,
    poses,
  ];
}
