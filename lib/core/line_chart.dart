import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'chart_geometry.dart';

typedef ChartPoint = ({double x, double y});

/// A line through [points] with a value axis of round numbers and labels
/// along the bottom. Tapping picks the point nearest across, whose
/// [pointLabel] then shows above the chart. Knows nothing of what it shows;
/// the callers' formatters write every label.
// Belongs in forge_ui; move it there when that package next changes.
class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.points,
    required this.xLabel,
    required this.yLabel,
    required this.pointLabel,
  });

  /// Ordered by x.
  final List<ChartPoint> points;
  final String Function(double x) xLabel;
  final String Function(double y) yLabel;

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
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
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
              final layout = _ChartLayout(
                size: constraints.biggest,
                points: widget.points,
                xLabel: widget.xLabel,
                yLabel: widget.yLabel,
                style: labelStyle,
                textDirection: textDirection,
                textScaler: textScaler,
              );
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

/// A painted label and where its anchor value sits on its axis.
typedef _Label = ({TextPainter text, double at});

/// Where everything goes for [size]: the plot area inside the labels, the
/// points and the labels of both axes.
class _ChartLayout {
  factory _ChartLayout({
    required Size size,
    required List<ChartPoint> points,
    required String Function(double x) xLabel,
    required String Function(double y) yLabel,
    required TextStyle? style,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    TextPainter label(String text) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();

    if (points.isEmpty) {
      return _ChartLayout._(Offset.zero & size, const [], const [], const []);
    }
    final xs = [for (final point in points) point.x];
    final ys = [for (final point in points) point.y];
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final yTicks = niceTicks(ys.reduce(math.min), ys.reduce(math.max));
    final yTexts = [for (final tick in yTicks) label(yLabel(tick))];
    final ends = [label(xLabel(minX)), label(xLabel(maxX))];
    final xWidth = ends.map((text) => text.width).reduce(math.max);
    final lineHeight = ends.first.height;
    for (final text in ends) {
      text.dispose();
    }
    final yWidth = yTexts.map((text) => text.width).reduce(math.max);
    final plot = Rect.fromLTRB(
      yWidth + Gap.sm,
      lineHeight / 2,
      size.width - xWidth / 2,
      size.height - lineHeight - Gap.xs,
    );
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
    final xCount = math.min(
      points.length,
      labelsThatFit(plot.width, xWidth, gap: Gap.md),
    );
    return _ChartLayout._(
      plot,
      [for (final point in points) Offset(x(point.x), y(point.y))],
      [for (final (i, tick) in yTicks.indexed) (text: yTexts[i], at: y(tick))],
      [
        for (final tick in spreadTicks(minX, maxX, xCount))
          (text: label(xLabel(tick)), at: x(tick)),
      ],
    );
  }

  _ChartLayout._(this.plot, this.positions, this.yLabels, this.xLabels);

  final Rect plot;
  final List<Offset> positions;
  final List<_Label> yLabels;
  final List<_Label> xLabels;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.layout,
    required this.selected,
    required this.line,
    required this.grid,
  });

  final _ChartLayout layout;
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
      text.paint(
        canvas,
        Offset(plot.left - Gap.sm - text.width, at - text.height / 2),
      );
    }
    for (final (:text, :at) in layout.xLabels) {
      final left = (at - text.width / 2).clamp(0.0, size.width - text.width);
      text.paint(canvas, Offset(left, plot.bottom + Gap.xs));
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
      oldDelegate.selected != selected ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid;
}
