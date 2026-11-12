import 'dart:math' as math;
import 'dart:ui';

/// Round values covering [min] to [max] for a value axis: about [count]
/// steps of 1, 2 or 5 × 10ⁿ, from a multiple of the step at or below [min]
/// to one at or above [max].
///
/// [precision] is the smallest difference the labels show (1 for whole
/// numbers, 0.1 for one decimal): a step is never smaller, so no two
/// labels read the same, and values closer together than [count] steps of
/// it get an axis that wide around them, so a tiny change does not fill
/// the height. The axis stays at or above zero when the values do. Empty
/// when either end is not finite.
List<double> niceTicks(
  double min,
  double max, {
  required double precision,
  int count = 4,
}) {
  if (!min.isFinite || !max.isFinite) return const [];
  var low = math.min(min, max);
  var high = math.max(min, max);
  final minSpan = precision * count;
  if (high - low < minSpan) {
    final middle = (low + high) / 2;
    low = middle - minSpan / 2;
    high = middle + minSpan / 2;
    if (low < 0 && math.min(min, max) >= 0) {
      high -= low;
      low = 0;
    }
  }
  final rough = (high - low) / math.max(count, 1);
  final magnitude = math
      .pow(10, (math.log(rough) / math.ln10).floor())
      .toDouble();
  final nice =
      magnitude *
      switch (rough / magnitude) {
        <= 1 => 1,
        <= 2 => 2,
        <= 5 => 5,
        _ => 10,
      };
  final step = math.max(nice, precision);
  // Rounds away the floating point error of adding up steps.
  final decimals = math.max(0, -(math.log(step) / math.ln10).floor());
  double round(double value) => double.parse(value.toStringAsFixed(decimals));
  final first = (low / step).floor();
  final last = (high / step).ceil();
  return [for (var i = first; i <= last; i++) round(i * step)];
}

/// Every k-th of [ticks] from the first, k as small as leaves at most
/// [fit] of them; the first alone when [fit] is below two.
List<double> thinTicks(List<double> ticks, int fit) {
  if (ticks.length <= fit) return ticks;
  if (fit < 2) return ticks.take(1).toList();
  final every = ((ticks.length - 1) / (fit - 1)).ceil();
  return [for (var i = 0; i < ticks.length; i += every) ticks[i]];
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

/// How many labels of [labelWidth], centred on evenly spaced points from
/// one end of [length] to the other, fit at least [gap] apart; at least
/// one.
int labelsThatFit(double length, double labelWidth, {required double gap}) {
  if (labelWidth <= 0) return 1;
  return math.max(1, (length / (labelWidth + gap)).floor() + 1);
}

/// Where a chart's parts go: the [plot] inside its labels, and how many
/// labels fit along each axis.
typedef ChartFrame = ({Rect plot, int yLabels, int xLabels});

/// The frame of a chart of [size] whose value labels, at most
/// [yLabelWidth] wide, sit left of the plot centred on their value, and
/// whose labels below it, at most [xLabelWidth] wide, are centred on
/// theirs; every label is [labelHeight] tall and [gap] from its
/// neighbours and the plot. The labels below start under the lowest value
/// label, so the two never meet at the corner.
ChartFrame chartFrame(
  Size size, {
  required double yLabelWidth,
  required double xLabelWidth,
  required double labelHeight,
  required double gap,
}) {
  final left = yLabelWidth + gap;
  final top = labelHeight / 2;
  final right = math.max(left, size.width - xLabelWidth / 2);
  final bottom = math.max(top, size.height - labelHeight * 1.5 - gap);
  final plot = Rect.fromLTRB(left, top, right, bottom);
  return (
    plot: plot,
    yLabels: labelsThatFit(plot.height, labelHeight, gap: gap),
    xLabels: labelsThatFit(plot.width, xLabelWidth, gap: gap),
  );
}

/// Where the labels below [plot] start, for labels [labelHeight] tall.
double xLabelsTop(Rect plot, double labelHeight, double gap) =>
    plot.bottom + labelHeight / 2 + gap;

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
