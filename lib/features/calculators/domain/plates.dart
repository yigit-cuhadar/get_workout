import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import 'calculation.dart';

const InputRange targetWeightRangeKg = (min: 1, max: 1000);
const InputRange barWeightRangeKg = (min: 0, max: 100);
const InputRange plateWeightRangeKg = (min: 0.25, max: 100);
const InputRange platePairsRange = (min: 0, max: 20);

/// How many plates of one size go on each side.
class PlateCount extends Equatable {
  const PlateCount({required this.weightKg, required this.count});

  final double weightKg;
  final int count;

  @override
  List<Object?> get props => [weightKg, count];
}

class PlateLoad extends Equatable {
  const PlateLoad({
    required this.perSide,
    required this.totalKg,
    required this.exact,
  });

  /// Largest first; sizes not used are left out.
  final List<PlateCount> perSide;

  /// Bar plus both sides.
  final double totalKg;

  /// False when the target cannot be reached and [totalKg] is the closest
  /// weight below it.
  final bool exact;

  @override
  List<Object?> get props => [perSide, totalKg, exact];
}

/// Weights are compared in whole grams. Pound plates are not whole grams
/// (45 lb = 20411.66 g), so the search may go this far over the target and
/// the total is summed from the real weights.
const _toleranceG = 10;

/// The plates per side that reach [targetKg] on a [barKg] bar, or the
/// heaviest load below it. Among loads of equal weight, the one using the
/// most of the largest plates (then the next largest, and so on) wins.
Calculation<PlateLoad> loadPlates({
  required double targetKg,
  required double barKg,
  required List<Plate> plates,
}) {
  final invalid = firstOutOfRange<PlateLoad>([
    (CalculatorInput.targetWeight, targetKg, targetWeightRangeKg),
    (CalculatorInput.barWeight, barKg, barWeightRangeKg),
  ]);
  if (invalid != null) return invalid;
  if (targetKg < barKg - _toleranceG / 1000) {
    return const Rejected(CalculatorProblem.targetBelowBar);
  }

  final sizes = [
    for (final plate in plates)
      if (plate.pairs > 0 && plate.weightKg > 0) plate,
  ]..sort((a, b) => b.weightKg.compareTo(a.weightKg));
  final perSideLimitG = ((targetKg - barKg) / 2 * 1000).floor() + _toleranceG;

  // Every reachable per-side weight with the counts that reach it first.
  // Sizes go largest first and counts high to low, so the first counts found
  // for a weight use the most large plates.
  var reachable = <int, List<int>>{0: const []};
  for (final plate in sizes) {
    final grams = (plate.weightKg * 1000).round();
    final next = <int, List<int>>{};
    for (final MapEntry(key: sum, value: counts) in reachable.entries) {
      for (var count = plate.pairs; count >= 0; count--) {
        final total = sum + count * grams;
        if (total <= perSideLimitG) {
          next.putIfAbsent(total, () => [...counts, count]);
        }
      }
    }
    reachable = next;
  }

  final best = reachable.keys.reduce((a, b) => a > b ? a : b);
  final counts = reachable[best]!;
  final perSide = [
    for (var i = 0; i < sizes.length; i++)
      if (counts[i] > 0)
        PlateCount(weightKg: sizes[i].weightKg, count: counts[i]),
  ];
  final totalKg = perSide.fold(
    barKg,
    (total, plate) => total + 2 * plate.count * plate.weightKg,
  );
  return Calculated(
    PlateLoad(
      perSide: perSide,
      totalKg: totalKg,
      exact: (totalKg - targetKg).abs() * 1000 <= _toleranceG,
    ),
  );
}

Calculation<double> checkBarWeight(double kg) =>
    firstOutOfRange<double>([
      (CalculatorInput.barWeight, kg, barWeightRangeKg),
    ]) ??
    Calculated(kg);

Calculation<Plate> checkPlate({required double weightKg, required int pairs}) =>
    firstOutOfRange<Plate>([
      (CalculatorInput.plateWeight, weightKg, plateWeightRangeKg),
      (CalculatorInput.platePairs, pairs.toDouble(), platePairsRange),
    ]) ??
    Calculated(Plate(weightKg: weightKg, pairs: pairs));
