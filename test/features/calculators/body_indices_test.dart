import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/body_indices.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';

void main() {
  BodyIndices value(Calculation<BodyIndices> result) =>
      (result as Calculated<BodyIndices>).value;

  test('BMI alone without body fat', () {
    // 80 / 1.8² = 24.69.
    final indices = value(calculateBodyIndices(weightKg: 80, heightCm: 180));
    expect(indices.bmi, closeTo(24.691, 0.001));
    expect(indices.ffmi, isNull);
    expect(indices.normalizedFfmi, isNull);
  });

  test('FFMI at 1.8 m equals its normalized value', () {
    // Lean 80 · 0.85 = 68; 68 / 3.24 = 20.99.
    final indices = value(
      calculateBodyIndices(weightKg: 80, heightCm: 180, bodyFatPercent: 15),
    );
    expect(indices.ffmi, closeTo(20.988, 0.001));
    expect(indices.normalizedFfmi, closeTo(indices.ffmi!, 1e-9));
  });

  test('normalized FFMI adds 6.1 per metre below 1.8 m', () {
    // Lean 70 · 0.8 = 56; 56 / 1.75² = 18.286; + 6.1 · 0.05 = 18.591.
    final indices = value(
      calculateBodyIndices(weightKg: 70, heightCm: 175, bodyFatPercent: 20),
    );
    expect(indices.bmi, closeTo(22.857, 0.001));
    expect(indices.ffmi, closeTo(18.286, 0.001));
    expect(indices.normalizedFfmi, closeTo(18.591, 0.001));
  });

  test('normalized FFMI subtracts above 1.8 m', () {
    // Lean 100 · 0.9 = 90; 90 / 1.9² = 24.931; − 6.1 · 0.1 = 24.321.
    final indices = value(
      calculateBodyIndices(weightKg: 100, heightCm: 190, bodyFatPercent: 10),
    );
    expect(indices.normalizedFfmi, closeTo(24.321, 0.001));
  });

  test('out-of-range inputs', () {
    expect(
      calculateBodyIndices(weightKg: 80, heightCm: 180, bodyFatPercent: 1),
      const OutOfRange<BodyIndices>(
        CalculatorInput.bodyFat,
        bodyFatRangePercent,
      ),
    );
    expect(
      calculateBodyIndices(weightKg: 80, heightCm: 260),
      const OutOfRange<BodyIndices>(CalculatorInput.height, heightRangeCm),
    );
    expect(
      calculateBodyIndices(weightKg: double.nan, heightCm: 180),
      isA<OutOfRange<BodyIndices>>(),
    );
  });
}
