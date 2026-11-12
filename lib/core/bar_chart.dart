import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'chart_geometry.dart';
import 'chart_text.dart';

/// One bar per value, oldest first, on a value axis of round numbers from
/// zero, with labels below as many bars as fit at the user's text size,
/// counted back from the last. An optional [target] is drawn across.
/// Tapping picks the nearest bar, whose [barLabel] then shows above the
/// chart. Knows nothing of what it shows; the callers' formatters write
/// every label.
// Belongs in forge_ui with LineChart; move it there when that package next
// changes.
class BarChart extends StatefulWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.xLabel,
    required this.yLabel,
    required this.yPrecision,
    required this.barLabel,
    required this.semanticLabel,
    this.target,
  });

  final List<double> values;

  /// The label below a bar, by its index in [values].
  final String Function(int index) xLabel;
  final String Function(double y) yLabel;

  /// The smallest difference [yLabel] shows, e.g. 1 for whole numbers; see
  /// [niceTicks].
  final double yPrecision;

  /// The text for the tapped bar, by its index in [values].
  final String Function(int index) barLabel;

  /// What the chart shows, values included, for screen readers.
  final String semanticLabel;

  /// A value marked by a line across the bars, e.g. a goal; the axis always
  /// reaches it.
  final double? target;

  /// Width to height of the drawing.
  static const _aspectRatio = 2.0;

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  int? _selected;

  @override
  void didUpdateWidget(BarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.values, widget.values)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = ChartText.of(context);
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Empty keeps its line, so the chart does not move on a tap.
        Text(
          selected == null ? '' : widget.barLabel(selected),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.sm),
        Semantics(
          label: widget.semanticLabel,
          child: AspectRatio(
            aspectRatio: BarChart._aspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = _BarLayout.of(constraints.biggest, widget, text);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => setState(
                    () => _selected = nearestIndex([
                      for (final bar in layout.bars) bar.center.dx,
                    ], details.localPosition.dx),
                  ),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _BarChartPainter(
                      layout: layout,
                      text: text,
                      selected: selected,
                      bar: colors.primary,
                      selectedBar: colors.tertiary,
                      target: colors.outline,
                      grid: colors.outlineVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A label and where its value sits along its axis.
typedef _Label = ({String text, double at});

/// Where everything goes: the plot inside the labels, the bars, the target
/// line and the labels of both axes.
class _BarLayout {
  const _BarLayout(
    this.plot,
    this.labelHeight,
    this.bars,
    this.targetY,
    this.yLabels,
    this.xLabels,
  );

  factory _BarLayout.of(Size size, BarChart chart, ChartText text) {
    final values = chart.values;
    final target = chart.target;
    if (values.isEmpty) {
      return _BarLayout(
        Offset.zero & size,
        0,
        const [],
        null,
        const [],
        const [],
      );
    }
    final yTicks = niceTicks(
      0,
      math.max(values.reduce(math.max), target ?? 0),
      precision: chart.yPrecision,
    );
    final ySizes = [
      for (final tick in yTicks) text.measure(chart.yLabel(tick)),
    ];
    final xSizes = [
      for (var i = 0; i < values.length; i++) text.measure(chart.xLabel(i)),
    ];
    final labelHeight = [
      ...ySizes,
      ...xSizes,
    ].map((size) => size.height).reduce(math.max);
    final frame = chartFrame(
      size,
      yLabelWidth: ySizes.map((size) => size.width).reduce(math.max),
      xLabelWidth: xSizes.map((size) => size.width).reduce(math.max),
      labelHeight: labelHeight,
      gap: Gap.sm,
    );
    final plot = frame.plot;
    double y(double value) => scale(
      value,
      domainMin: yTicks.first,
      domainMax: yTicks.last,
      rangeMin: plot.bottom,
      rangeMax: plot.top,
    );
    final bars = barRects(plot, values, top: yTicks.last);
    return _BarLayout(
      plot,
      labelHeight,
      bars,
      target == null ? null : y(target),
      [
        for (final tick in thinTicks(yTicks, frame.yLabels))
          (text: chart.yLabel(tick), at: y(tick)),
      ],
      [
        for (final index in labelledBars(values.length, frame.xLabels))
          (text: chart.xLabel(index), at: bars[index].center.dx),
      ],
    );
  }

  final Rect plot;
  final double labelHeight;
  final List<Rect> bars;
  final double? targetY;
  final List<_Label> yLabels;
  final List<_Label> xLabels;

  @override
  bool operator ==(Object other) =>
      other is _BarLayout &&
      other.plot == plot &&
      other.labelHeight == labelHeight &&
      other.targetY == targetY &&
      listEquals(other.bars, bars) &&
      listEquals(other.yLabels, yLabels) &&
      listEquals(other.xLabels, xLabels);

  @override
  int get hashCode => Object.hash(
    plot,
    labelHeight,
    targetY,
    Object.hashAll(bars),
    Object.hashAll(yLabels),
    Object.hashAll(xLabels),
  );
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.layout,
    required this.text,
    required this.selected,
    required this.bar,
    required this.selectedBar,
    required this.target,
    required this.grid,
  });

  final _BarLayout layout;
  final ChartText text;
  final int? selected;
  final Color bar;
  final Color selectedBar;
  final Color target;
  final Color grid;

  static const _gridWidth = 1.0;
  static const _targetWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = layout.plot;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = _gridWidth;
    for (final (:text, :at) in layout.yLabels) {
      canvas.drawLine(Offset(plot.left, at), Offset(plot.right, at), gridPaint);
      final label = this.text.painter(text);
      label.paint(
        canvas,
        Offset(plot.left - Gap.sm - label.width, at - label.height / 2),
      );
      label.dispose();
    }
    final top = xLabelsTop(plot, layout.labelHeight, Gap.sm);
    for (final (:text, :at) in layout.xLabels) {
      final label = this.text.painter(text);
      final left = math.max(
        0.0,
        math.min(at - label.width / 2, size.width - label.width),
      );
      label.paint(canvas, Offset(left, top));
      label.dispose();
    }
    final barPaint = Paint()..color = bar;
    final selectedPaint = Paint()..color = selectedBar;
    for (final (i, rect) in layout.bars.indexed) {
      canvas.drawRect(rect, i == selected ? selectedPaint : barPaint);
    }
    final targetY = layout.targetY;
    if (targetY != null) {
      canvas.drawLine(
        Offset(plot.left, targetY),
        Offset(plot.right, targetY),
        Paint()
          ..color = target
          ..strokeWidth = _targetWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.text != text ||
      oldDelegate.selected != selected ||
      oldDelegate.bar != bar ||
      oldDelegate.selectedBar != selectedBar ||
      oldDelegate.target != target ||
      oldDelegate.grid != grid;
}
