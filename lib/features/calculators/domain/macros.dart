import 'package:forge_core/forge_core.dart';

import 'calculation.dart';

const InputRange calorieRangeKcal = (min: 800, max: 10000);
const InputRange proteinRangeGPerKg = (min: 1.2, max: 2.4);
const InputRange fatRangePercent = (min: 20, max: 35);
const defaultProteinGPerKg = 1.8;
const defaultFatPercent = 25.0;

const _kcalPerGProtein = 4;
const _kcalPerGCarbs = 4;
const _kcalPerGFat = 9;

class Macros extends Equatable {
  const Macros({
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  final double proteinG;
  final double fatG;
  final double carbsG;

  @override
  List<Object?> get props => [proteinG, fatG, carbsG];
}

/// Protein from body weight, fat as a share of calories, carbohydrate from
/// what is left.
Calculation<Macros> splitMacros({
  required double calories,
  required double weightKg,
  double proteinGPerKg = defaultProteinGPerKg,
  double fatPercent = defaultFatPercent,
}) {
  final invalid = firstOutOfRange<Macros>([
    (CalculatorInput.calories, calories, calorieRangeKcal),
    (CalculatorInput.bodyWeight, weightKg, bodyWeightRangeKg),
    (CalculatorInput.proteinPerKg, proteinGPerKg, proteinRangeGPerKg),
    (CalculatorInput.fatPercent, fatPercent, fatRangePercent),
  ]);
  if (invalid != null) return invalid;

  final proteinG = proteinGPerKg * weightKg;
  final fatKcal = calories * fatPercent / 100;
  final carbsKcal = calories - proteinG * _kcalPerGProtein - fatKcal;
  if (carbsKcal < 0) return const Rejected(CalculatorProblem.negativeCarbs);
  return Calculated(
    Macros(
      proteinG: proteinG,
      fatG: fatKcal / _kcalPerGFat,
      carbsG: carbsKcal / _kcalPerGCarbs,
    ),
  );
}
