import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../body/domain/body_stats.dart';
import '../../strength/domain/strength.dart';

/// What the Progress tab shows of the body log.
class BodySnapshot extends Equatable {
  const BodySnapshot({
    this.latestKg,
    this.weights = const [],
    this.latestBodyFat,
  });

  final double? latestKg;

  /// The weights of the last 12 weeks, oldest first.
  final List<WeightPoint> weights;

  /// The newest entry's body fat that has one, with that entry's date.
  final BodyFatPoint? latestBodyFat;

  @override
  List<Object?> get props => [latestKg, weights, latestBodyFat];
}

/// The [BodySnapshot] of [entries] (newest first), whose body fat by entry
/// id is [bodyFat] (see [bodyFatByEntry]).
BodySnapshot bodySnapshot(
  List<BodyEntry> entries,
  Map<String, double> bodyFat, {
  required DateTime now,
}) {
  BodyFatPoint? latestBodyFat;
  for (final entry in entries) {
    if (bodyFat[entry.id] case final percent?) {
      latestBodyFat = (date: entry.date, percent: percent);
      break;
    }
  }
  return BodySnapshot(
    latestKg: latestWeightKg(entries),
    weights: weightSeries(entries, range: StrengthRange.weeks12, now: now),
    latestBodyFat: latestBodyFat,
  );
}
