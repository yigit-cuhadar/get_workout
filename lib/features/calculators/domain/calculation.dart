import 'package:forge_core/forge_core.dart';

/// An input of a calculator, named so the UI can show a problem next to it.
enum CalculatorInput {
  bodyWeight,
  height,
  age,
  neck,
  waist,
  hip,
  liftedWeight,
  reps,
  targetWeight,
  barWeight,
  plateWeight,
  platePairs,
  calories,
  proteinPerKg,
  fatPercent,
  bodyFat,
}

/// A combination of inputs a formula cannot use, beyond a single range.
enum CalculatorProblem {
  /// The body fat formula gives an impossible result for these measurements.
  checkMeasurements,

  /// Epley is unreliable above 12 reps.
  tooManyReps,
  targetBelowBar,
  negativeCarbs,
}

/// Inclusive bounds in the formula's metric unit (kg, cm, years, kcal, ...).
typedef InputRange = ({double min, double max});

/// Outcome of a calculator: a value, or why the inputs cannot give one. The
/// typed reasons let the UI word each one, which a plain `ValidationFailure`
/// message cannot.
sealed class Calculation<T> extends Equatable {
  const Calculation();
}

final class Calculated<T> extends Calculation<T> {
  const Calculated(this.value);
  final T value;

  @override
  List<Object?> get props => [value];
}

final class OutOfRange<T> extends Calculation<T> {
  const OutOfRange(this.input, this.range);
  final CalculatorInput input;
  final InputRange range;

  @override
  List<Object?> get props => [input, range];
}

final class Rejected<T> extends Calculation<T> {
  const Rejected(this.problem);
  final CalculatorProblem problem;

  @override
  List<Object?> get props => [problem];
}

/// The first input outside its range, if any.
OutOfRange<T>? firstOutOfRange<T>(
  Iterable<(CalculatorInput, double, InputRange)> checks,
) {
  for (final (input, value, range) in checks) {
    // Also catches NaN, which fails every comparison.
    if (!(value >= range.min && value <= range.max)) {
      return OutOfRange(input, range);
    }
  }
  return null;
}

/// Plausible adult ranges shared by the body calculators.
const InputRange bodyWeightRangeKg = (min: 30, max: 300);
const InputRange heightRangeCm = (min: 100, max: 250);
const InputRange bodyFatRangePercent = (min: 2, max: 60);
