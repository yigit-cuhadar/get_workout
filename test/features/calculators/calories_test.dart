import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';

void main() {
  CalorieEstimate estimate({
    Sex sex = Sex.male,
    double weightKg = 80,
    double heightCm = 180,
    double ageYears = 30,
    ActivityLevel activity = ActivityLevel.moderate,
  }) => (estimateCalories(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    ageYears: ageYears,
    activity: activity,
  ) as Calculated<CalorieEstimate>).value;

  test('male BMR and targets', () {
    // 10·80 + 6.25·180 − 5·30 + 5 = 800 + 1125 − 150 + 5 = 1780;
    // × 1.55 = 2759.
    final result = estimate();
    expect(result.bmr, closeTo(1780, 1e-9));
    expect(result.maintenance, closeTo(2759, 1e-9));
    expect(result.lose.kcal, closeTo(2259, 1e-9));
    expect(result.loseSlowly.kcal, closeTo(2509, 1e-9));
    expect(result.gain.kcal, closeTo(3009, 1e-9));
    expect(
      [result.lose, result.loseSlowly, result.gain].any((t) => t.floored),
      isFalse,
    );
  });

  test('female BMR, with the deepest cut floored at 1,200 kcal', () {
    // 10·60 + 6.25·165 − 5·30 − 161 = 600 + 1031.25 − 150 − 161 = 1320.25;
    // × 1.2 = 1584.3; −500 = 1084.3 < 1200.
    final result = estimate(
      sex: Sex.female,
      weightKg: 60,
      heightCm: 165,
      activity: ActivityLevel.sedentary,
    );
    expect(result.bmr, closeTo(1320.25, 1e-9));
    expect(result.maintenance, closeTo(1584.3, 1e-9));
    expect(result.lose, const CalorieTarget(kcal: 1200, floored: true));
    expect(result.loseSlowly.kcal, closeTo(1334.3, 1e-9));
    expect(result.loseSlowly.floored, isFalse);
    expect(result.gain.floored, isFalse);
  });

  test('male targets are floored at 1,500 kcal; maintenance never is', () {
    // 10·50 + 6.25·160 − 5·70 + 5 = 1155; × 1.2 = 1386.
    final result = estimate(
      weightKg: 50,
      heightCm: 160,
      ageYears: 70,
      activity: ActivityLevel.sedentary,
    );
    expect(result.maintenance, closeTo(1386, 1e-9));
    expect(result.lose, const CalorieTarget(kcal: 1500, floored: true));
    expect(result.loseSlowly, const CalorieTarget(kcal: 1500, floored: true));
    expect(result.gain.kcal, closeTo(1636, 1e-9));
    expect(result.gain.floored, isFalse);
  });

  test('a target exactly at the floor is not flagged', () {
    // Female BMR 1320.25 at 60/165/30; pick a weight so maintenance − 500
    // is exactly 1200: maintenance 1700 / 1.2 = 1416.67 BMR.
    final weight = (1700 / 1.2 - 6.25 * 165 + 5 * 30 + 161) / 10;
    final result = estimate(
      sex: Sex.female,
      weightKg: weight,
      heightCm: 165,
      activity: ActivityLevel.sedentary,
    );
    expect(result.lose.kcal, closeTo(1200, 1e-9));
    expect(result.lose.floored, isFalse);
  });

  test('activity factors', () {
    const factors = {
      ActivityLevel.sedentary: 1.2,
      ActivityLevel.light: 1.375,
      ActivityLevel.moderate: 1.55,
      ActivityLevel.active: 1.725,
      ActivityLevel.veryActive: 1.9,
    };
    for (final MapEntry(key: level, value: factor) in factors.entries) {
      expect(
        estimate(activity: level).maintenance,
        closeTo(1780 * factor, 1e-9),
        reason: '$level',
      );
    }
  });

  group('rejects out-of-range input', () {
    Calculation<CalorieEstimate> calculate({
      double weightKg = 80,
      double heightCm = 180,
      double ageYears = 30,
    }) => estimateCalories(
      sex: Sex.male,
      weightKg: weightKg,
      heightCm: heightCm,
      ageYears: ageYears,
      activity: ActivityLevel.moderate,
    );

    test('weight', () {
      expect(
        calculate(weightKg: 29.9),
        const OutOfRange<CalorieEstimate>(
          CalculatorInput.bodyWeight,
          bodyWeightRangeKg,
        ),
      );
      expect(calculate(weightKg: 300.1), isA<OutOfRange<CalorieEstimate>>());
      expect(
        calculate(weightKg: double.nan),
        isA<OutOfRange<CalorieEstimate>>(),
      );
    });

    test('height and age', () {
      expect(
        calculate(heightCm: 99),
        const OutOfRange<CalorieEstimate>(
          CalculatorInput.height,
          heightRangeCm,
        ),
      );
      expect(
        calculate(ageYears: 14),
        const OutOfRange<CalorieEstimate>(CalculatorInput.age, ageRangeYears),
      );
      expect(calculate(ageYears: 101), isA<OutOfRange<CalorieEstimate>>());
    });

    test('bounds are inclusive', () {
      expect(
        calculate(weightKg: 30, heightCm: 250, ageYears: 15),
        isA<Calculated<CalorieEstimate>>(),
      );
    });
  });
}
