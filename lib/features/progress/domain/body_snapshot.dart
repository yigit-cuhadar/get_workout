import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../body/domain/body_stats.dart';
import '../../strength/domain/strength.dart';
import 'progress_usecases.dart';

/// One entry's body fat.
typedef BodyFatPoint = ({DateTime date, double percent});

/// What the Progress tab shows of the body log.
class BodySnapshot extends Equatable {
  const BodySnapshot({
    this.latest,
    this.weights = const [],
    this.weeks = StrengthRange.freeWeeks,
    this.latestBodyFat,
  });

  /// The newest weigh-in.
  final WeightPoint? latest;

  /// The weights of the last [weeks] ([cardWeeks]), oldest first.
  final List<WeightPoint> weights;
  final int weeks;

  /// The newest entry's body fat that has one, with that entry's date.
  final BodyFatPoint? latestBodyFat;

  /// The change over [weights], from the first to the last; null with
  /// fewer than two.
  KgChange? get change => weights.length < 2
      ? null
      : (
          kg: weights.last.kg - weights.first.kg,
          weeks: changeWeeks(weights.first.date, weights.last.date),
        );

  @override
  List<Object?> get props => [latest, weights, weeks, latestBodyFat];
}

/// The [BodySnapshot] of [entries] (newest first) over the last [weeks],
/// whose body fat by entry id is [bodyFat] (see [bodyFatByEntry]).
BodySnapshot bodySnapshot(
  List<BodyEntry> entries,
  Map<String, double> bodyFat, {
  required DateTime now,
  required int weeks,
}) {
  BodyFatPoint? latestBodyFat;
  for (final entry in entries) {
    if (bodyFat[entry.id] case final percent?) {
      latestBodyFat = (date: entry.date, percent: percent);
      break;
    }
  }
  final latest = entries.where((entry) => entry.weightKg != null).firstOrNull;
  return BodySnapshot(
    latest: latest == null ? null : (date: latest.date, kg: latest.weightKg!),
    weights: weightsSince(entries, weeksBefore(now, weeks)),
    weeks: weeks,
    latestBodyFat: latestBodyFat,
  );
}
