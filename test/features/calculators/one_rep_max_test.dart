import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/one_rep_max.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  Calculation<OneRepMax> estimate(
    double weightKg,
    int reps, {
    double incrementKg = 2.5,
  }) => estimateOneRepMax(
    weightKg: weightKg,
    reps: reps,
    incrementKg: incrementKg,
  );

  OneRepMax value(Calculation<OneRepMax> result) =>
      (result as Calculated<OneRepMax>).value;

  test('Epley estimate', () {
    // 100 · (1 + 5/30) = 116.67.
    expect(value(estimate(100, 5)).estimateKg, closeTo(116.667, 0.001));
    // 100 · (1 + 12/30) = 140.
    expect(value(estimate(100, 12)).estimateKg, closeTo(140, 1e-9));
  });

  test('a single rep is the weight itself', () {
    // Epley would give 100 · (1 + 1/30) = 103.3.
    expect(value(estimate(100, 1)).estimateKg, 100);
  });

  test('loads from 50 to 95 % rounded to 2.5 kg', () {
    // 116.67 · p, to the nearest 2.5: 58.3→57.5, 64.2→65, 70→70,
    // 75.8→75, 81.7→82.5, 87.5→87.5, 93.3→92.5, 99.2→100, 105→105,
    // 110.8→110.
    final loads = value(estimate(100, 5)).loads;
    expect(loads.map((l) => l.percent), [
      50,
      55,
      60,
      65,
      70,
      75,
      80,
      85,
      90,
      95,
    ]);
    final expected = [57.5, 65, 70, 75, 82.5, 87.5, 92.5, 100, 105, 110];
    for (var i = 0; i < loads.length; i++) {
      expect(loads[i].weightKg, closeTo(expected[i], 1e-9));
    }
  });

  test('loads rounded to 5 lb when the increment is 5 lb', () {
    // 225 lb × 5 → 262.5 lb; 90 % = 236.25 → 235 lb.
    final result = value(
      estimate(WeightUnit.lb.toKg(225), 5, incrementKg: WeightUnit.lb.toKg(5)),
    );
    expect(WeightUnit.lb.fromKg(result.estimateKg), closeTo(262.5, 1e-9));
    final ninety = result.loads.firstWhere((l) => l.percent == 90);
    expect(WeightUnit.lb.fromKg(ninety.weightKg), closeTo(235, 1e-9));
    for (final load in result.loads) {
      final lb = WeightUnit.lb.fromKg(load.weightKg);
      expect(lb % 5, anyOf(closeTo(0, 1e-6), closeTo(5, 1e-6)));
    }
  });

  test('more than 12 reps is rejected', () {
    expect(
      estimate(100, 13),
      const Rejected<OneRepMax>(CalculatorProblem.tooManyReps),
    );
  });

  test('fewer than one rep is out of range', () {
    expect(
      estimate(100, 0),
      const OutOfRange<OneRepMax>(CalculatorInput.reps, (min: 1, max: 12)),
    );
    expect(estimate(100, -1), isA<OutOfRange<OneRepMax>>());
  });

  test('the weight must be positive and plausible', () {
    expect(
      estimate(0, 5),
      const OutOfRange<OneRepMax>(
        CalculatorInput.liftedWeight,
        liftedWeightRangeKg,
      ),
    );
    expect(estimate(1001, 5), isA<OutOfRange<OneRepMax>>());
    expect(estimate(double.nan, 5), isA<OutOfRange<OneRepMax>>());
  });
}
