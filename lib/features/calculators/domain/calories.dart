import 'package:forge_core/forge_core.dart';

import 'calculation.dart';

/// The two sexes the Mifflin-St Jeor and US Navy formulas define.
enum Sex { male, female }

enum ActivityLevel {
  sedentary(1.2),
  light(1.375),
  moderate(1.55),
  active(1.725),
  veryActive(1.9);

  const ActivityLevel(this.factor);
  final double factor;
}

class CalorieTarget extends Equatable {
  const CalorieTarget({required this.kcal, required this.floored});

  final double kcal;

  /// Raised to the minimum intake for the sex instead of the plain offset.
  final bool floored;

  @override
  List<Object?> get props => [kcal, floored];
}

class CalorieEstimate extends Equatable {
  const CalorieEstimate({
    required this.bmr,
    required this.maintenance,
    required this.lose,
    required this.loseSlowly,
    required this.gain,
  });

  final double bmr;
  final double maintenance;

  /// Maintenance −500, −250 and +250 kcal.
  final CalorieTarget lose;
  final CalorieTarget loseSlowly;
  final CalorieTarget gain;

  @override
  List<Object?> get props => [bmr, maintenance, lose, loseSlowly, gain];
}

const InputRange ageRangeYears = (min: 15, max: 100);

/// Daily intake targets never go below these.
double minimumIntakeKcal(Sex sex) => switch (sex) {
  Sex.male => 1500,
  Sex.female => 1200,
};

/// Mifflin-St Jeor BMR times the activity factor.
Calculation<CalorieEstimate> estimateCalories({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required double ageYears,
  required ActivityLevel activity,
}) {
  final invalid = firstOutOfRange<CalorieEstimate>([
    (CalculatorInput.bodyWeight, weightKg, bodyWeightRangeKg),
    (CalculatorInput.height, heightCm, heightRangeCm),
    (CalculatorInput.age, ageYears, ageRangeYears),
  ]);
  if (invalid != null) return invalid;

  final bmr =
      10 * weightKg +
      6.25 * heightCm -
      5 * ageYears +
      switch (sex) {
        Sex.male => 5,
        Sex.female => -161,
      };
  final maintenance = bmr * activity.factor;
  final floor = minimumIntakeKcal(sex);
  CalorieTarget target(double offset) {
    final kcal = maintenance + offset;
    return kcal < floor
        ? CalorieTarget(kcal: floor, floored: true)
        : CalorieTarget(kcal: kcal, floored: false);
  }

  return Calculated(
    CalorieEstimate(
      bmr: bmr,
      maintenance: maintenance,
      lose: target(-500),
      loseSlowly: target(-250),
      gain: target(250),
    ),
  );
}
