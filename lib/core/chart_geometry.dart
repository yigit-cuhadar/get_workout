import 'dart:math' as math;

/// Round values covering [min] to [max] for a value axis: about [count]
/// steps of 1, 2 or 5 × 10ⁿ, from a multiple of the step at or below [min]
/// to one at or above [max]. A single value gets an axis around it. Empty
/// when either end is not finite.
List<double> niceTicks(double min, double max, {int count = 4}) {
  if (!min.isFinite || !max.isFinite) return const [];
  var low = math.min(min, max);
  var high = math.max(min, max);
  if (low == high) {
    final pad = low == 0 ? 1.0 : low.abs() / 10;
    low -= pad;
    high += pad;
  }
  final rough = (high - low) / math.max(count, 1);
  final magnitude = math
      .pow(10, (math.log(rough) / math.ln10).floor())
      .toDouble();
  final step =
      magnitude *
      switch (rough / magnitude) {
        <= 1 => 1,
        <= 2 => 2,
        <= 5 => 5,
        _ => 10,
      };
  // Rounds away the floating point error of adding up steps.
  final decimals = math.max(0, -(math.log(step) / math.ln10).floor());
  double round(double value) => double.parse(value.toStringAsFixed(decimals));
  final first = (low / step).floor();
  final last = (high / step).ceil();
  return [for (var i = first; i <= last; i++) round(i * step)];
}

/// [value] mapped from [domainMin]..[domainMax] onto [rangeMin]..[rangeMax];
/// a domain of no width maps everything to the middle of the range.
double scale(
  double value, {
  required double domainMin,
  required double domainMax,
  required double rangeMin,
  required double rangeMax,
}) {
  final span = domainMax - domainMin;
  if (span == 0) return (rangeMin + rangeMax) / 2;
  return rangeMin + (value - domainMin) / span * (rangeMax - rangeMin);
}

/// [count] evenly spaced values from [min] to [max], both included; just
/// [min] when they are equal or [count] is below two.
List<double> spreadTicks(double min, double max, int count) {
  if (min == max || count < 2) return [min];
  return [
    for (var i = 0; i < count; i++)
      i == count - 1 ? max : min + (max - min) * i / (count - 1),
  ];
}

/// How many labels of [labelWidth], [gap] apart, fit in [width]; at least
/// one.
int labelsThatFit(double width, double labelWidth, {required double gap}) {
  if (labelWidth <= 0) return 1;
  return math.max(1, ((width + gap) / (labelWidth + gap)).floor());
}

/// The index of the value in [xs] nearest to [x]; null when [xs] is empty.
int? nearestIndex(List<double> xs, double x) {
  int? nearest;
  for (var i = 0; i < xs.length; i++) {
    if (nearest == null || (xs[i] - x).abs() < (xs[nearest] - x).abs()) {
      nearest = i;
    }
  }
  return nearest;
}
