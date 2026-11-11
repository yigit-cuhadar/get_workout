import '../../settings/domain/user_settings.dart';
import 'body_fat.dart';
import 'body_indices.dart';
import 'calculation.dart';
import 'calories.dart';
import 'macros.dart';
import 'one_rep_max.dart';
import 'plates.dart';

// Calculators are pure and synchronous, so these are plain callables rather
// than the async `UseCase`, like `WatchSettings`.

class EstimateCalories {
  const EstimateCalories();

  Calculation<CalorieEstimate> call({
    required Sex sex,
    required double weightKg,
    required double heightCm,
    required double ageYears,
    required ActivityLevel activity,
  }) => estimateCalories(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    ageYears: ageYears,
    activity: activity,
  );
}

class EstimateBodyFat {
  const EstimateBodyFat();

  Calculation<double> call({
    required Sex sex,
    required double heightCm,
    required double neckCm,
    required double waistCm,
    double? hipCm,
  }) => estimateBodyFat(
    sex: sex,
    heightCm: heightCm,
    neckCm: neckCm,
    waistCm: waistCm,
    hipCm: hipCm,
  );
}

class EstimateOneRepMax {
  const EstimateOneRepMax();

  Calculation<OneRepMax> call({
    required double weightKg,
    required int reps,
    required double incrementKg,
  }) => estimateOneRepMax(
    weightKg: weightKg,
    reps: reps,
    incrementKg: incrementKg,
  );
}

class LoadPlates {
  const LoadPlates();

  Calculation<PlateLoad> call({
    required double targetKg,
    required double barKg,
    required List<Plate> plates,
  }) => loadPlates(targetKg: targetKg, barKg: barKg, plates: plates);
}

class CheckBarWeight {
  const CheckBarWeight();

  Calculation<double> call(double kg) => checkBarWeight(kg);
}

class CheckPlate {
  const CheckPlate();

  Calculation<Plate> call({required double weightKg, required int pairs}) =>
      checkPlate(weightKg: weightKg, pairs: pairs);
}

class SplitMacros {
  const SplitMacros();

  Calculation<Macros> call({
    required double calories,
    required double weightKg,
    required double proteinGPerKg,
    required double fatPercent,
  }) => splitMacros(
    calories: calories,
    weightKg: weightKg,
    proteinGPerKg: proteinGPerKg,
    fatPercent: fatPercent,
  );
}

class CalculateBodyIndices {
  const CalculateBodyIndices();

  Calculation<BodyIndices> call({
    required double weightKg,
    required double heightCm,
    double? bodyFatPercent,
  }) => calculateBodyIndices(
    weightKg: weightKg,
    heightCm: heightCm,
    bodyFatPercent: bodyFatPercent,
  );
}
