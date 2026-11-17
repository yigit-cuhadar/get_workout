import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../../core/widgets/number_sheet.dart';
import '../domain/body_fat.dart';
import '../domain/calculation.dart';
import '../domain/calories.dart';
import '../domain/macros.dart';
import '../domain/one_rep_max.dart';
import '../domain/plates.dart';

/// Turns metric calculator values into text in the user's units, and
/// calculator problems into messages.
class CalculatorFormat {
  CalculatorFormat(
    this.l10n, {
    required this.weightUnit,
    required this.lengthUnit,
  }) : _locale = l10n.localeName;

  final AppLocalizations l10n;
  final WeightUnit weightUnit;
  final LengthUnit lengthUnit;
  final String _locale;

  String get weightUnitLabel => switch (weightUnit) {
    WeightUnit.kg => l10n.unitKg,
    WeightUnit.lb => l10n.unitLb,
  };

  String get lengthUnitLabel => switch (lengthUnit) {
    LengthUnit.cm => l10n.unitCm,
    LengthUnit.inch => l10n.unitIn,
  };

  String number(double value, {int decimals = 0}) =>
      NumberFormat.decimalPatternDigits(
        locale: _locale,
        decimalDigits: decimals,
      ).format(value);

  /// Trailing zeros dropped, so 2.5 and 1.25 kg plates read naturally.
  String weight(double kg, {int maxDecimals = 1}) =>
      '${weightNumber(kg, maxDecimals: maxDecimals)} $weightUnitLabel';

  /// A weekly rate of change as the calorie targets name it: 0.25 kg,
  /// not rounded to 0.3.
  String weeklyRate(double kg) => weight(kg, maxDecimals: 2);

  /// [weight] without the unit.
  String weightNumber(double kg, {int maxDecimals = 1}) =>
      _trimmed(weightUnit.fromKg(kg), maxDecimals);

  String _trimmed(double value, int maxDecimals) =>
      (NumberFormat.decimalPattern(
        _locale,
      )..maximumFractionDigits = maxDecimals).format(value);

  /// A weight as an editable number in the user's unit, without grouping.
  String editableWeight(double kg) {
    final text = weightUnit.fromKg(kg).toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String kcal(double value) => l10n.calcKcal(number(value));

  /// The message for an input, if the result is about that input.
  String? errorFor(CalculatorInput input, Calculation<Object?>? result) =>
      switch (result) {
        OutOfRange(input: final failed, :final range) when failed == input =>
          _outOfRange(input, range),
        Rejected(problem: CalculatorProblem.tooManyReps)
            when input == CalculatorInput.reps =>
          l10n.calcTooManyReps,
        Rejected(problem: CalculatorProblem.targetBelowBar)
            when input == CalculatorInput.targetWeight =>
          l10n.calcTargetBelowBar,
        _ => null,
      };

  /// The message for a problem that is not about one input.
  String? generalError(Calculation<Object?>? result) => switch (result) {
    Rejected(problem: CalculatorProblem.checkMeasurements) =>
      l10n.calcCheckMeasurements,
    Rejected(problem: CalculatorProblem.negativeCarbs) =>
      l10n.calcNegativeCarbs,
    _ => null,
  };

  /// What the number sheet of [input] takes, in the user's unit.
  NumberBounds boundsOf(CalculatorInput input) {
    final (min, max) = _shownBounds(input, _rangeOf(input));
    return NumberBounds(min, max, decimals: _decimalsOf(input));
  }

  /// The sheet's message for a value outside [boundsOf].
  String rangeError(CalculatorInput input) =>
      _outOfRange(input, _rangeOf(input));

  /// [value], in the user's unit, as an input row shows it.
  String shown(CalculatorInput input, double value) =>
      _trimmed(value, _decimalsOf(input));

  /// "Add your height and activity to see the result." for [missing],
  /// each as [missingName] calls it.
  String addToSee(List<String> missing) => l10n.calcAddToSee(
    missing.length == 1
        ? missing.single
        : l10n.calcAnd(
            missing.sublist(0, missing.length - 1).join(', '),
            missing.last,
          ),
  );

  static InputRange _rangeOf(CalculatorInput input) => switch (input) {
    CalculatorInput.bodyWeight => bodyWeightRangeKg,
    CalculatorInput.height => heightRangeCm,
    CalculatorInput.age => ageRangeYears,
    CalculatorInput.neck => neckRangeCm,
    CalculatorInput.waist => waistRangeCm,
    CalculatorInput.hip => hipRangeCm,
    CalculatorInput.liftedWeight => liftedWeightRangeKg,
    CalculatorInput.reps => repsRange,
    CalculatorInput.targetWeight => targetWeightRangeKg,
    CalculatorInput.barWeight => barWeightRangeKg,
    CalculatorInput.plateWeight => plateWeightRangeKg,
    CalculatorInput.platePairs => platePairsRange,
    CalculatorInput.calories => calorieRangeKcal,
    CalculatorInput.proteinPerKg => proteinRangeGPerKg,
    CalculatorInput.fatPercent => fatRangePercent,
    CalculatorInput.bodyFat => bodyFatRangePercent,
  };

  /// How many decimals an input takes.
  static int _decimalsOf(CalculatorInput input) => switch (input) {
    CalculatorInput.liftedWeight ||
    CalculatorInput.targetWeight ||
    CalculatorInput.barWeight ||
    CalculatorInput.plateWeight => 2,
    CalculatorInput.bodyWeight ||
    CalculatorInput.height ||
    CalculatorInput.neck ||
    CalculatorInput.waist ||
    CalculatorInput.hip ||
    CalculatorInput.proteinPerKg ||
    CalculatorInput.bodyFat => 1,
    CalculatorInput.age ||
    CalculatorInput.reps ||
    CalculatorInput.platePairs ||
    CalculatorInput.calories ||
    CalculatorInput.fatPercent => 0,
  };

  String _outOfRange(CalculatorInput input, InputRange range) {
    final (min, max) = _shownBounds(input, range);
    return l10n.calcOutOfRange(
      _trimmed(min, _boundDecimals(input)),
      _trimmed(max, _boundDecimals(input)),
    );
  }

  /// [range] in the user's unit, rounded inwards so a value at a shown
  /// bound is accepted.
  (double, double) _shownBounds(CalculatorInput input, InputRange range) {
    final convert = switch (input) {
      CalculatorInput.bodyWeight ||
      CalculatorInput.targetWeight ||
      CalculatorInput.barWeight ||
      CalculatorInput.liftedWeight ||
      CalculatorInput.plateWeight => weightUnit.fromKg,
      CalculatorInput.height ||
      CalculatorInput.neck ||
      CalculatorInput.waist ||
      CalculatorInput.hip => lengthUnit.fromCm,
      _ => (double value) => value,
    };
    final factor = math.pow(10, _boundDecimals(input));
    return (
      (convert(range.min) * factor).ceil() / factor,
      (convert(range.max) * factor).floor() / factor,
    );
  }

  static int _boundDecimals(CalculatorInput input) => switch (input) {
    CalculatorInput.liftedWeight || CalculatorInput.proteinPerKg => 1,
    CalculatorInput.plateWeight => 2,
    _ => 0,
  };
}

extension CalculatorText on AppLocalizations {
  String calcSexLabel(Sex sex) => switch (sex) {
    Sex.male => calcSexMale,
    Sex.female => calcSexFemale,
  };

  String calcActivityLabel(ActivityLevel level) => switch (level) {
    ActivityLevel.sedentary => calcActivitySedentary,
    ActivityLevel.light => calcActivityLight,
    ActivityLevel.moderate => calcActivityModerate,
    ActivityLevel.active => calcActivityActive,
    ActivityLevel.veryActive => calcActivityVeryActive,
  };
}
