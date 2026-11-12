import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'chart_geometry.dart';
import 'chart_text.dart';

typedef ChartPoint = ({double x, double y});

/// A line through [points] with a value axis of round numbers and labels
/// along the bottom, as many as fit at the user's text size. Tapping picks
/// the point nearest across, whose [pointLabel] then shows above the
/// chart. Knows nothing of what it shows; the callers' formatters write
/// every label.
// Belongs in forge_ui; move it there when that package next changes.
class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.points,
    required this.xLabel,
    required this.yLabel,
    required this.yPrecision,
    required this.pointLabel,
  });

  /// Ordered by x.
  final List<ChartPoint> points;
  final String Function(double x) xLabel;
  final String Function(double y) yLabel;

  /// The smallest difference [yLabel] shows, e.g. 1 for whole numbers; see
  /// [niceTicks].
  final double yPrecision;

  /// The text for the tapped point, by its index in [points].
  final String Function(int index) pointLabel;

  /// Width to height of the drawing.
  static const _aspectRatio = 1.6;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _selected;

  @override
  void didUpdateWidget(LineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.points, widget.points)) _selected = null;
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
          selected == null ? '' : widget.pointLabel(selected),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.sm),
        AspectRatio(
          aspectRatio: LineChart._aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _ChartLayout.of(constraints.biggest, widget, text);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => setState(
                  () => _selected = nearestIndex([
                    for (final position in layout.positions) position.dx,
                  ], details.localPosition.dx),
                ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LineChartPainter(
                    layout: layout,
                    text: text,
                    selected: selected,
                    line: colors.primary,
                    grid: colors.outlineVariant,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A label and where its value sits along its axis.
typedef _Label = ({String text, double at});

/// Where everything goes: the plot inside the labels, the points and the
/// labels of both axes.
class _ChartLayout {
  const _ChartLayout(
    this.plot,
    this.labelHeight,
    this.positions,
    this.yLabels,
    this.xLabels,
  );

  factory _ChartLayout.of(Size size, LineChart chart, ChartText text) {
    final points = chart.points;
    if (points.isEmpty) {
      return _ChartLayout(Offset.zero & size, 0, const [], const [], const []);
    }
    final xs = [for (final point in points) point.x];
    final ys = [for (final point in points) point.y];
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final yTicks = niceTicks(
      ys.reduce(math.min),
      ys.reduce(math.max),
      precision: chart.yPrecision,
    );
    final ySizes = [
      for (final tick in yTicks) text.measure(chart.yLabel(tick)),
    ];
    final xSizes = [
      text.measure(chart.xLabel(minX)),
      text.measure(chart.xLabel(maxX)),
    ];
    final labelHeight = [
      ...ySizes,
      ...xSizes,
    ].map((size) => size.height).reduce(math.max);
    final xWidth = xSizes.map((size) => size.width).reduce(math.max);
    final frame = chartFrame(
      size,
      yLabelWidth: ySizes.map((size) => size.width).reduce(math.max),
      xLabelWidth: xWidth,
      labelHeight: labelHeight,
      gap: Gap.sm,
    );
    final plot = frame.plot;
    double x(double value) => scale(
      value,
      domainMin: minX,
      domainMax: maxX,
      rangeMin: plot.left,
      rangeMax: plot.right,
    );
    double y(double value) => scale(
      value,
      domainMin: yTicks.first,
      domainMax: yTicks.last,
      rangeMin: plot.bottom,
      rangeMax: plot.top,
    );
    return _ChartLayout(
      plot,
      labelHeight,
      [for (final point in points) Offset(x(point.x), y(point.y))],
      [
        for (final tick in thinTicks(yTicks, frame.yLabels))
          (text: chart.yLabel(tick), at: y(tick)),
      ],
      [
        for (final tick in spreadTicks(
          minX,
          maxX,
          math.min(points.length, frame.xLabels),
        ))
          (text: chart.xLabel(tick), at: x(tick)),
      ],
    );
  }

  final Rect plot;
  final double labelHeight;
  final List<Offset> positions;
  final List<_Label> yLabels;
  final List<_Label> xLabels;

  @override
  bool operator ==(Object other) =>
      other is _ChartLayout &&
      other.plot == plot &&
      other.labelHeight == labelHeight &&
      listEquals(other.positions, positions) &&
      listEquals(other.yLabels, yLabels) &&
      listEquals(other.xLabels, xLabels);

  @override
  int get hashCode => Object.hash(
    plot,
    labelHeight,
    Object.hashAll(positions),
    Object.hashAll(yLabels),
    Object.hashAll(xLabels),
  );
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.layout,
    required this.text,
    required this.selected,
    required this.line,
    required this.grid,
  });

  final _ChartLayout layout;
  final ChartText text;
  final int? selected;
  final Color line;
  final Color grid;

  static const _lineWidth = 2.0;
  static const _gridWidth = 1.0;
  static const _dotRadius = 3.0;
  static const _selectedRadius = 6.0;

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
    final positions = layout.positions;
    if (positions.isEmpty) return;
    final selected = this.selected;
    if (selected != null && selected < positions.length) {
      final x = positions[selected].dx;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = _lineWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..addPolygon(positions, false), linePaint);
    final dotPaint = Paint()..color = line;
    for (final (i, position) in positions.indexed) {
      canvas.drawCircle(
        position,
        i == selected ? _selectedRadius : _dotRadius,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.text != text ||
      oldDelegate.selected != selected ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid;
}
