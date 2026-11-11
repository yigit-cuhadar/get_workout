import 'dart:math' as math;

import 'calculation.dart';
import 'calories.dart';

const InputRange neckRangeCm = (min: 20, max: 80);
const InputRange waistRangeCm = (min: 40, max: 250);
const InputRange hipRangeCm = (min: 50, max: 250);

double _log10(double x) => math.log(x) / math.ln10;

/// US Navy body fat percentage from circumferences in cm. [hipCm] is used
/// (and required) only for women.
Calculation<double> estimateBodyFat({
  required Sex sex,
  required double heightCm,
  required double neckCm,
  required double waistCm,
  double? hipCm,
}) {
  final invalid = firstOutOfRange<double>([
    (CalculatorInput.height, heightCm, heightRangeCm),
    (CalculatorInput.neck, neckCm, neckRangeCm),
    (CalculatorInput.waist, waistCm, waistRangeCm),
    if (sex == Sex.female)
      (CalculatorInput.hip, hipCm ?? double.nan, hipRangeCm),
  ]);
  if (invalid != null) return invalid;

  final girth = switch (sex) {
    Sex.male => waistCm - neckCm,
    Sex.female => waistCm + hipCm! - neckCm,
  };
  // The logarithm needs a positive girth; anything else is a mis-measurement.
  if (girth <= 0) return const Rejected(CalculatorProblem.checkMeasurements);

  final density = switch (sex) {
    Sex.male => 1.0324 - 0.19077 * _log10(girth) + 0.15456 * _log10(heightCm),
    Sex.female =>
      1.29579 - 0.35004 * _log10(girth) + 0.22100 * _log10(heightCm),
  };
  final percent = 495 / density - 450;
  if (!(percent >= bodyFatRangePercent.min &&
      percent <= bodyFatRangePercent.max)) {
    return const Rejected(CalculatorProblem.checkMeasurements);
  }
  return Calculated(percent);
}
