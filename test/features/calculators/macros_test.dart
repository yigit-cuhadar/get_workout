import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/macros.dart';

void main() {
  Macros value(Calculation<Macros> result) =>
      (result as Calculated<Macros>).value;

  test('defaults: 1.8 g/kg protein, 25 % fat', () {
    // Protein 1.8 · 80 = 144 g = 576 kcal; fat 2500 · 0.25 = 625 kcal
    // = 69.44 g; carbohydrate (2500 − 576 − 625) / 4 = 324.75 g.
    final macros = value(splitMacros(calories: 2500, weightKg: 80));
    expect(macros.proteinG, closeTo(144, 1e-9));
    expect(macros.fatG, closeTo(69.444, 0.001));
    expect(macros.carbsG, closeTo(324.75, 1e-9));
  });

  test('adjusted protein and fat', () {
    // Protein 2.4 · 70 = 168 g = 672 kcal; fat 35 % of 2000 = 700 kcal
    // = 77.78 g; carbohydrate 628 / 4 = 157 g.
    final macros = value(
      splitMacros(
        calories: 2000,
        weightKg: 70,
        proteinGPerKg: 2.4,
        fatPercent: 35,
      ),
    );
    expect(macros.proteinG, closeTo(168, 1e-9));
    expect(macros.fatG, closeTo(77.778, 0.001));
    expect(macros.carbsG, closeTo(157, 1e-9));
  });

  test('the calories add up', () {
    final macros = value(splitMacros(calories: 3100, weightKg: 92));
    expect(
      macros.proteinG * 4 + macros.fatG * 9 + macros.carbsG * 4,
      closeTo(3100, 1e-9),
    );
  });

  test('zero carbohydrate is allowed', () {
    // Protein 2 · 100 = 800 kcal, fat 20 % of 1000 = 200 kcal.
    final macros = value(
      splitMacros(
        calories: 1000,
        weightKg: 100,
        proteinGPerKg: 2,
        fatPercent: 20,
      ),
    );
    expect(macros.carbsG, closeTo(0, 1e-9));
  });

  test('negative carbohydrate is rejected', () {
    // Protein 2.4 · 150 = 360 g = 1440 kcal > 1200.
    expect(
      splitMacros(calories: 1200, weightKg: 150, proteinGPerKg: 2.4),
      const Rejected<Macros>(CalculatorProblem.negativeCarbs),
    );
  });

  test('out-of-range inputs', () {
    expect(
      splitMacros(calories: 799, weightKg: 80),
      const OutOfRange<Macros>(CalculatorInput.calories, calorieRangeKcal),
    );
    expect(
      splitMacros(calories: 2000, weightKg: 80, proteinGPerKg: 1.1),
      const OutOfRange<Macros>(
        CalculatorInput.proteinPerKg,
        proteinRangeGPerKg,
      ),
    );
    expect(
      splitMacros(calories: 2000, weightKg: 80, fatPercent: 36),
      const OutOfRange<Macros>(CalculatorInput.fatPercent, fatRangePercent),
    );
    expect(
      splitMacros(calories: 2000, weightKg: 10),
      const OutOfRange<Macros>(CalculatorInput.bodyWeight, bodyWeightRangeKg),
    );
  });
}
