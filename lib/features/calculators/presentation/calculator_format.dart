import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';

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
  String weight(double kg, {int maxDecimals = 1}) {
    final format = NumberFormat.decimalPattern(_locale)
      ..maximumFractionDigits = maxDecimals;
    return '${format.format(weightUnit.fromKg(kg))} $weightUnitLabel';
  }

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

  /// Bounds are rounded inwards, so a value at a shown bound is accepted.
  String _outOfRange(CalculatorInput input, InputRange range) {
    String bounds(double Function(double) convert, int decimals) {
      final factor = math.pow(10, decimals);
      final min = (convert(range.min) * factor).ceil() / factor;
      final max = (convert(range.max) * factor).floor() / factor;
      return l10n.calcOutOfRange(
        number(min, decimals: decimals),
        number(max, decimals: decimals),
      );
    }

    double same(double value) => value;
    return switch (input) {
      CalculatorInput.bodyWeight ||
      CalculatorInput.targetWeight ||
      CalculatorInput.barWeight => bounds(weightUnit.fromKg, 0),
      CalculatorInput.liftedWeight => bounds(weightUnit.fromKg, 1),
      CalculatorInput.plateWeight => bounds(weightUnit.fromKg, 2),
      CalculatorInput.height ||
      CalculatorInput.neck ||
      CalculatorInput.waist ||
      CalculatorInput.hip => bounds(lengthUnit.fromCm, 0),
      CalculatorInput.proteinPerKg => bounds(same, 1),
      CalculatorInput.age ||
      CalculatorInput.reps ||
      CalculatorInput.platePairs ||
      CalculatorInput.calories ||
      CalculatorInput.fatPercent ||
      CalculatorInput.bodyFat => bounds(same, 0),
    };
  }
}
