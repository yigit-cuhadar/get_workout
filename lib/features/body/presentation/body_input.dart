import 'package:flutter/services.dart';

import '../../calculators/presentation/calculator_input.dart';
import '../../cardio/presentation/cardio_text.dart';
import '../../settings/domain/user_settings.dart';

/// A stored metric value as an input shows it, in the user's unit: at most
/// one decimal.
String metricText(double? metric, double Function(double) fromMetric) =>
    metric == null ? '' : formatDecimal(fromMetric(metric), 1);

/// The metric value [text] holds; null while empty, NaN when it is no
/// number. A [stored] value whose text was left as shown is kept as is, so
/// saving other changes never drifts it by rounding.
double? readMetric(
  String text, {
  required double? stored,
  required double Function(double) fromMetric,
  required double Function(double) toMetric,
}) {
  if (stored != null && text == metricText(stored, fromMetric)) return stored;
  final value = readNumber(text);
  return value == null ? null : toMetric(value);
}

/// Digits and decimal separators only, so nothing like "1e9" or "NaN" can be typed;
/// the cubits still check what they read.
final decimalInput = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  LengthLimitingTextInputFormatter(6),
];

/// [kg] as a weight ruler in [unit] shows it: to the nearest 0.1.
double rulerWeight(double kg, WeightUnit unit) =>
    (unit.fromKg(kg) * 10).round() / 10;

/// The kg a weight ruler's [value] in [unit] stands for: [stored] while
/// the ruler still shows it, so saving other changes never drifts it.
double rulerWeightKg(double value, WeightUnit unit, {double? stored}) =>
    stored != null && rulerWeight(stored, unit) == value
    ? stored
    : unit.toKg(value);
