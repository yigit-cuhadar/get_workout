import 'package:forge_core/forge_core.dart';

import '../../profile/domain/user_profile.dart';
import '../../settings/domain/user_settings.dart';
import 'calculation.dart';

export '../../profile/domain/user_profile.dart' show Sex;

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
    required this.maintenance,
    required this.lose,
    required this.gain,
  });

  final double maintenance;

  /// Maintenance less the weekly loss. Null when the minimum intake leaves
  /// no deficit, as a "lose" target at or above maintenance is no deficit.
  final CalorieTarget? lose;

  /// Maintenance plus the weekly gain.
  final CalorieTarget gain;

  @override
  List<Object?> get props => [maintenance, lose, gain];
}

/// The energy in a kilo of body weight, for weekly change targets.
const kcalPerKg = 7700;

/// The daily kcal that adds up to [kg] of body weight a week.
double dailyKcalForWeekly(double kg) => kg * kcalPerKg / 7;

/// The weekly change of the lose and gain targets, in kg: 0.5 and 0.25 kg,
/// or 1 and 0.5 lb for a user weighing in pounds.
({double lose, double gain}) weeklyChangeKg(WeightUnit unit) => switch (unit) {
  WeightUnit.kg => (lose: 0.5, gain: 0.25),
  WeightUnit.lb => (lose: WeightUnit.lb.toKg(1), gain: WeightUnit.lb.toKg(0.5)),
};

const InputRange ageRangeYears = (min: 15, max: 100);

/// Daily intake targets never go below these.
double minimumIntakeKcal(Sex sex) => switch (sex) {
  Sex.male => 1500,
  Sex.female => 1200,
};

/// Mifflin-St Jeor BMR times the activity factor, with targets to lose
/// [loseKgPerWeek] and gain [gainKgPerWeek].
Calculation<CalorieEstimate> estimateCalories({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required double ageYears,
  required ActivityLevel activity,
  required double loseKgPerWeek,
  required double gainKgPerWeek,
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

  // At least a whole kcal below, so it never shows as equal to maintenance.
  CalorieTarget? deficit(double offset) {
    final candidate = target(offset);
    return maintenance - candidate.kcal >= 1 ? candidate : null;
  }

  return Calculated(
    CalorieEstimate(
      maintenance: maintenance,
      lose: deficit(-dailyKcalForWeekly(loseKgPerWeek)),
      gain: target(dailyKcalForWeekly(gainKgPerWeek)),
    ),
  );
}
