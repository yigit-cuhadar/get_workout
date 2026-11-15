import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../body/domain/body_stats.dart';
import '../../strength/domain/strength.dart';

/// One entry's body fat.
typedef BodyFatPoint = ({DateTime date, double percent});

/// What the Progress tab shows of the body log.
class BodySnapshot extends Equatable {
  const BodySnapshot({
    this.latest,
    this.previous,
    this.weights = const [],
    this.latestBodyFat,
  });

  /// The newest weigh-in.
  final WeightPoint? latest;

  /// The weigh-in before [latest].
  final WeightPoint? previous;

  /// The weights of the last 12 weeks, oldest first.
  final List<WeightPoint> weights;

  /// The newest entry's body fat that has one, with that entry's date.
  final BodyFatPoint? latestBodyFat;

  /// The change since the [previous] weigh-in, in kg.
  double? get change => switch ((latest, previous)) {
    (final latest?, final previous?) => latest.kg - previous.kg,
    _ => null,
  };

  @override
  List<Object?> get props => [latest, previous, weights, latestBodyFat];
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
  final weighIns = [
    for (final entry in entries)
      if (entry.weightKg case final kg?) (date: entry.date, kg: kg),
  ];
  return BodySnapshot(
    latest: weighIns.firstOrNull,
    previous: weighIns.skip(1).firstOrNull,
    weights: weightSeries(entries, range: StrengthRange.weeks12, now: now),
    latestBodyFat: latestBodyFat,
  );
}
