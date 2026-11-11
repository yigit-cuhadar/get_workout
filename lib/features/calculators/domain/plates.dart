import 'dart:math' as math;
import 'dart:typed_data';

import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import 'calculation.dart';

const InputRange targetWeightRangeKg = (min: 1, max: 1000);
const InputRange barWeightRangeKg = (min: 0, max: maxBarWeightKg);
const InputRange plateWeightRangeKg = (
  min: minPlateWeightKg,
  max: maxPlateWeightKg,
);
// Records cannot convert the int constant; equal to maxPlatePairs.
const InputRange platePairsRange = (min: 0, max: 20);

/// Rounding noise allowed between a loaded total and the target. A load is
/// never heavier than the target by more than this.
const plateToleranceKg = 0.001;

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

/// The plates per side that reach [targetKg] on a [barKg] bar, or the
/// heaviest load below it. Among loads of equal weight, the one using the
/// most of the largest plates (then the next largest, and so on) wins. At
/// most [maxPlateSizes] sizes of [maxPlatePairs] pairs are used, which keeps
/// the search to a few million steps.
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
  if (targetKg < barKg - plateToleranceKg) {
    return const Rejected(CalculatorProblem.targetBelowBar);
  }

  final sizes = [
    for (final plate in plates)
      if (plate.pairs > 0 && (plate.weightKg * 1000).round() > 0)
        Plate(
          weightKg: plate.weightKg,
          pairs: math.min(plate.pairs, maxPlatePairs),
        ),
  ]..sort((a, b) => b.weightKg.compareTo(a.weightKg));
  return Calculated(
    _PlateSearch(sizes.take(maxPlateSizes).toList(), barKg).load(targetKg),
  );
}

/// Bounded knapsack over whole grams per side. Plates are rounded to grams
/// for the search only; every candidate is checked with its real weight.
class _PlateSearch {
  _PlateSearch(this.sizes, this.barKg)
    : grams = [for (final size in sizes) (size.weightKg * 1000).round()];

  final List<Plate> sizes;
  final List<int> grams;
  final double barKg;

  PlateLoad load(double targetKg) {
    final perSideLimitG = ((targetKg + plateToleranceKg - barKg) / 2 * 1000)
        .floor();
    // Rounding each plate to grams is off by up to half a gram per plate, so
    // sums this far apart may be in either order by real weight.
    final plateCount = sizes.fold(0, (count, size) => count + size.pairs);
    final slackG = (plateCount / 2).ceil() + 1;
    var capacityG = 0;
    for (var i = 0; i < sizes.length; i++) {
      capacityG += grams[i] * sizes[i].pairs;
    }
    final searchG = math.max(0, math.min(capacityG, perSideLimitG + slackG));
    final reachable = _reachable(searchG);

    PlateLoad? best;
    int? bestSum;
    for (var sum = searchG; sum >= 0; sum--) {
      if (bestSum != null && sum < bestSum - slackG) break;
      if (reachable[0][sum] == 0) continue;
      final counts = _counts(sum, reachable);
      var totalKg = barKg;
      for (var i = 0; i < sizes.length; i++) {
        totalKg += 2 * counts[i] * sizes[i].weightKg;
      }
      if (totalKg > targetKg + plateToleranceKg) continue;
      if (best == null || totalKg > best.totalKg + 1e-9) {
        best = PlateLoad(
          perSide: [
            for (var i = 0; i < sizes.length; i++)
              if (counts[i] > 0)
                PlateCount(weightKg: sizes[i].weightKg, count: counts[i]),
          ],
          totalKg: totalKg,
          exact: targetKg - totalKg <= plateToleranceKg,
        );
        bestSum ??= sum;
        if (best.exact) break;
      }
    }
    // The empty bar is always reachable and never above the target.
    return best!;
  }

  /// `reachable[i][g]` is 1 when sizes `i..` can make exactly `g` grams per
  /// side; the last table holds only 0.
  List<Uint8List> _reachable(int maxG) {
    final tables = List.generate(sizes.length + 1, (_) => Uint8List(maxG + 1));
    tables[sizes.length][0] = 1;
    for (var i = sizes.length - 1; i >= 0; i--) {
      final next = tables[i + 1];
      final current = tables[i];
      final step = grams[i];
      final span = step * sizes[i].pairs;
      // Along each residue, a sum is reachable when a reachable sum of the
      // smaller sizes lies at most `pairs` steps below it.
      for (var residue = 0; residue < step && residue <= maxG; residue++) {
        var lastReachable = -1;
        for (var sum = residue; sum <= maxG; sum += step) {
          if (next[sum] == 1) lastReachable = sum;
          if (lastReachable >= 0 && sum - lastReachable <= span) {
            current[sum] = 1;
          }
        }
      }
    }
    return tables;
  }

  /// The counts making [sum] with the most of each size, largest first.
  List<int> _counts(int sum, List<Uint8List> reachable) {
    final counts = List.filled(sizes.length, 0);
    var rest = sum;
    for (var i = 0; i < sizes.length; i++) {
      var count = math.min(sizes[i].pairs, rest ~/ grams[i]);
      while (reachable[i + 1][rest - count * grams[i]] == 0) {
        count--;
      }
      counts[i] = count;
      rest -= count * grams[i];
    }
    return counts;
  }
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
