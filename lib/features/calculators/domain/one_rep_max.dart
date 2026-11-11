import 'package:forge_core/forge_core.dart';

import '../../../core/one_rep_max.dart';
import 'calculation.dart';

const InputRange liftedWeightRangeKg = (min: 0.5, max: 1000);

class PercentLoad extends Equatable {
  const PercentLoad({required this.percent, required this.weightKg});

  final int percent;

  /// Rounded to the nearest loadable increment.
  final double weightKg;

  @override
  List<Object?> get props => [percent, weightKg];
}

class OneRepMax extends Equatable {
  const OneRepMax({required this.estimateKg, required this.loads});

  final double estimateKg;

  /// 50 to 95 % in 5 % steps.
  final List<PercentLoad> loads;

  @override
  List<Object?> get props => [estimateKg, loads];
}

/// See [epleyOneRepMax]. [incrementKg] is the smallest step the user can
/// load (2.5 kg, or 5 lb expressed in kg), so table loads land on real bar
/// weights.
Calculation<OneRepMax> estimateOneRepMax({
  required double weightKg,
  required int reps,
  required double incrementKg,
}) {
  final invalid = firstOutOfRange<OneRepMax>([
    (CalculatorInput.liftedWeight, weightKg, liftedWeightRangeKg),
  ]);
  if (invalid != null) return invalid;
  if (reps < 1) {
    return OutOfRange(CalculatorInput.reps, (
      min: 1,
      max: maxEpleyReps.toDouble(),
    ));
  }
  if (reps > maxEpleyReps) return const Rejected(CalculatorProblem.tooManyReps);
  assert(incrementKg > 0, 'incrementKg must be positive');

  final estimate = epleyOneRepMax(weightKg, reps)!;
  return Calculated(
    OneRepMax(
      estimateKg: estimate,
      loads: [
        for (var percent = 50; percent <= 95; percent += 5)
          PercentLoad(
            percent: percent,
            weightKg:
                (estimate * percent / 100 / incrementKg).round() * incrementKg,
          ),
      ],
    ),
  );
}
