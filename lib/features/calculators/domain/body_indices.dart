import 'package:forge_core/forge_core.dart';

import 'calculation.dart';

class BodyIndices extends Equatable {
  const BodyIndices({required this.bmi, this.ffmi, this.normalizedFfmi});

  final double bmi;

  /// Only with a body fat percentage.
  final double? ffmi;

  /// [ffmi] adjusted to a height of 1.8 m.
  final double? normalizedFfmi;

  @override
  List<Object?> get props => [bmi, ffmi, normalizedFfmi];
}

/// BMI, and FFMI when [bodyFatPercent] is known.
Calculation<BodyIndices> calculateBodyIndices({
  required double weightKg,
  required double heightCm,
  double? bodyFatPercent,
}) {
  final invalid = firstOutOfRange<BodyIndices>([
    (CalculatorInput.bodyWeight, weightKg, bodyWeightRangeKg),
    (CalculatorInput.height, heightCm, heightRangeCm),
    if (bodyFatPercent != null)
      (CalculatorInput.bodyFat, bodyFatPercent, bodyFatRangePercent),
  ]);
  if (invalid != null) return invalid;

  final heightM = heightCm / 100;
  final squared = heightM * heightM;
  if (bodyFatPercent == null) {
    return Calculated(BodyIndices(bmi: weightKg / squared));
  }
  final ffmi = weightKg * (1 - bodyFatPercent / 100) / squared;
  return Calculated(
    BodyIndices(
      bmi: weightKg / squared,
      ffmi: ffmi,
      normalizedFfmi: ffmi + 6.1 * (1.8 - heightM),
    ),
  );
}
