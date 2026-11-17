import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

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
    loseKgPerWeek: 0.5,
    gainKgPerWeek: 0.25,
  ) as Calculated<CalorieEstimate>).value;

  test('maintenance and the weekly targets at 7,700 kcal per kg', () {
    // BMR 10·80 + 6.25·180 − 5·30 + 5 = 1780; × 1.55 = 2759.
    // 0.5 kg a week = 550 kcal a day, 0.25 kg = 275.
    final result = estimate();
    expect(result.maintenance, closeTo(2759, 1e-9));
    expect(result.lose, const CalorieTarget(kcal: 2209, floored: false));
    expect(result.gain, const CalorieTarget(kcal: 3034, floored: false));
  });

  test('daily kcal for a weekly change', () {
    expect(dailyKcalForWeekly(0.5), closeTo(550, 1e-9));
    expect(dailyKcalForWeekly(0.25), closeTo(275, 1e-9));
  });

  test('kg users change 0.5 and 0.25 kg a week, lb users 1 and 0.5 lb', () {
    expect(weeklyChangeKg(WeightUnit.kg), (lose: 0.5, gain: 0.25));
    final lb = weeklyChangeKg(WeightUnit.lb);
    expect(lb.lose, closeTo(0.45359237, 1e-12));
    expect(lb.gain, closeTo(0.45359237 / 2, 1e-12));
  });

  test('female BMR, with the loss floored at 1,200 kcal', () {
    // 10·60 + 6.25·165 − 5·30 − 161 = 1320.25; × 1.2 = 1584.3;
    // −550 = 1034.3 < 1200.
    final result = estimate(
      sex: Sex.female,
      weightKg: 60,
      heightCm: 165,
      activity: ActivityLevel.sedentary,
    );
    expect(result.maintenance, closeTo(1584.3, 1e-9));
    expect(result.lose, const CalorieTarget(kcal: 1200, floored: true));
    expect(result.gain.kcal, closeTo(1859.3, 1e-9));
    expect(result.gain.floored, isFalse);
  });

  test('male loss is floored at 1,500 kcal', () {
    // 10·70 + 6.25·165 − 5·60 + 5 = 1436.25; × 1.375 = 1974.84;
    // −550 = 1424.84 < 1500.
    final result = estimate(
      weightKg: 70,
      heightCm: 165,
      ageYears: 60,
      activity: ActivityLevel.light,
    );
    expect(result.maintenance, closeTo(1974.84, 0.01));
    expect(result.lose, const CalorieTarget(kcal: 1500, floored: true));
  });

  test('no loss is offered when the floor is not below maintenance', () {
    // 10·50 + 6.25·160 − 5·70 + 5 = 1155; × 1.2 = 1386 < 1500.
    final male = estimate(
      weightKg: 50,
      heightCm: 160,
      ageYears: 70,
      activity: ActivityLevel.sedentary,
    );
    expect(male.maintenance, closeTo(1386, 1e-9));
    expect(male.lose, isNull);
    expect(male.gain.kcal, closeTo(1661, 1e-9));
  });

  test('a floored loss equal to maintenance is not offered', () {
    // Male maintenance exactly 1500 (BMR 1250 sedentary).
    final weight = (1250 - 6.25 * 170 + 5 * 40 - 5) / 10;
    final result = estimate(
      weightKg: weight,
      heightCm: 170,
      ageYears: 40,
      activity: ActivityLevel.sedentary,
    );
    expect(result.maintenance, closeTo(1500, 1e-9));
    expect(result.lose, isNull);
  });

  test('a target exactly at the floor is not flagged', () {
    // Female, maintenance 1750 so that − 550 is exactly 1200.
    final weight = (1750 / 1.2 - 6.25 * 165 + 5 * 30 + 161) / 10;
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
      loseKgPerWeek: 0.5,
      gainKgPerWeek: 0.25,
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
