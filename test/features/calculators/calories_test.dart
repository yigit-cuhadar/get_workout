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
    expect(result.lose!.kcal, closeTo(2259, 1e-9));
    expect(result.loseSlowly!.kcal, closeTo(2509, 1e-9));
    expect(result.gain.kcal, closeTo(3009, 1e-9));
    expect(
      [result.lose!, result.loseSlowly!, result.gain].any((t) => t.floored),
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
    expect(result.loseSlowly!.kcal, closeTo(1334.3, 1e-9));
    expect(result.loseSlowly!.floored, isFalse);
    expect(result.gain.floored, isFalse);
  });

  test('male deficits are floored at 1,500 kcal', () {
    // 10·70 + 6.25·165 − 5·60 + 5 = 1436.25; × 1.375 = 1974.84;
    // −500 = 1474.84 < 1500; −250 = 1724.84.
    final result = estimate(
      weightKg: 70,
      heightCm: 165,
      ageYears: 60,
      activity: ActivityLevel.light,
    );
    expect(result.maintenance, closeTo(1974.84, 0.01));
    expect(result.lose, const CalorieTarget(kcal: 1500, floored: true));
    expect(result.loseSlowly!.kcal, closeTo(1724.84, 0.01));
    expect(result.loseSlowly!.floored, isFalse);
  });

  test('no deficit is offered when the floor is not below maintenance', () {
    // 10·50 + 6.25·160 − 5·70 + 5 = 1155; × 1.2 = 1386 < 1500.
    final male = estimate(
      weightKg: 50,
      heightCm: 160,
      ageYears: 70,
      activity: ActivityLevel.sedentary,
    );
    expect(male.maintenance, closeTo(1386, 1e-9));
    expect(male.lose, isNull);
    expect(male.loseSlowly, isNull);
    expect(male.gain.kcal, closeTo(1636, 1e-9));

    // 10·50 + 6.25·155 − 5·65 − 161 = 982.75; × 1.2 = 1179.3 < 1200.
    final female = estimate(
      sex: Sex.female,
      weightKg: 50,
      heightCm: 155,
      ageYears: 65,
      activity: ActivityLevel.sedentary,
    );
    expect(female.maintenance, closeTo(1179.3, 1e-9));
    expect(female.lose, isNull);
    expect(female.loseSlowly, isNull);
    expect(female.gain.kcal, closeTo(1429.3, 1e-9));
  });

  test('a floored deficit equal to maintenance is not offered', () {
    // Male maintenance exactly 1500 (BMR 1250 sedentary): −250 floors to
    // 1500, which is no deficit.
    final weight = (1250 - 6.25 * 170 + 5 * 40 - 5) / 10;
    final result = estimate(
      weightKg: weight,
      heightCm: 170,
      ageYears: 40,
      activity: ActivityLevel.sedentary,
    );
    expect(result.maintenance, closeTo(1500, 1e-9));
    expect(result.loseSlowly, isNull);
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
    expect(result.lose!.kcal, closeTo(1200, 1e-9));
    expect(result.lose!.floored, isFalse);
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
