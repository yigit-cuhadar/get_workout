import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/chart_geometry.dart';
import '../../../core/chart_text.dart';
import '../../../core/line_chart.dart';

/// Where a series' values are labelled.
enum SeriesAxis { left, right, none }

/// One series of a [SeriesChart]: a line through its points, or bars.
@immutable
class ChartSeries {
  const ChartSeries({
    required this.points,
    required this.color,
    required this.ticks,
    required this.axis,
    required this.yLabel,
    this.bars = false,
    this.guide,
  });

  /// Ordered by x. A bar spans [SeriesChart.barSpan] from its x.
  final List<ChartPoint> points;
  final Color color;

  /// The series' own scale, round values from the bottom of the plot to
  /// the top (see [niceTicks]); labelled on [axis] by [yLabel].
  final List<double> ticks;
  final SeriesAxis axis;
  final String Function(double y) yLabel;

  /// Bars behind the lines rather than a line.
  final bool bars;

  /// A value marked by a dashed line across, e.g. a target.
  final double? guide;

  @override
  bool operator ==(Object other) =>
      other is ChartSeries &&
      listEquals(other.points, points) &&
      other.color == color &&
      listEquals(other.ticks, ticks) &&
      other.axis == axis &&
      other.bars == bars &&
      other.guide == guide;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    color,
    Object.hashAll(ticks),
    axis,
    bars,
    guide,
  );
}

/// Several series over one x range, each on its own scale: lines, and bars
/// behind them, side by side where several bar series share a span. At
/// most one series is labelled on each side; the left one also gives the
/// grid. Labels along the bottom, as many as fit at the user's text size.
/// Tapping picks the point nearest across, of any series, and shows
/// [selectionLabel] of its x above the chart. Knows nothing of what it
/// shows; the callers' formatters write every label.
// Belongs in forge_ui with LineChart and BarChart; move it there when that
// package next changes.
class SeriesChart extends StatefulWidget {
  const SeriesChart({
    super.key,
    required this.series,
    required this.xMin,
    required this.xMax,
    required this.barSpan,
    required this.xLabel,
    required this.selectionLabel,
  });

  final List<ChartSeries> series;
  final double xMin;
  final double xMax;

  /// How far along x a bar spans from its point.
  final double barSpan;
  final String Function(double x) xLabel;

  /// The text for the tapped x, one of the points' x.
  final String Function(double x) selectionLabel;

  /// Width to height of the drawing.
  static const _aspectRatio = 1.6;

  @override
  State<SeriesChart> createState() => _SeriesChartState();
}

class _SeriesChartState extends State<SeriesChart> {
  double? _selected;

  @override
  void didUpdateWidget(SeriesChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.series, widget.series)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = ChartText.of(context);
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Empty keeps its line, so the chart does not move on a tap.
        Text(
          selected == null ? '' : widget.selectionLabel(selected),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.sm),
        AspectRatio(
          aspectRatio: SeriesChart._aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _Layout.of(constraints.biggest, widget, text);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final targets = layout.targets;
                  final nearest = nearestIndex([
                    for (final target in targets) target.at,
                  ], details.localPosition.dx);
                  if (nearest == null) return;
                  setState(() => _selected = targets[nearest].x);
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _Painter(
                    layout: layout,
                    text: text,
                    selectedAt: selected == null
                        ? null
                        : layout.targets
                              .firstWhere((target) => target.x == selected)
                              .at,
                    grid: theme.colorScheme.outlineVariant,
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

/// A null [color] is the labels' own.
typedef _Label = ({String text, double at, Color? color});

/// One series placed: its line's points or its bars, and its guide.
typedef _Placed = ({
  Color color,
  List<Offset> line,
  List<Rect> bars,
  double? guide,
});

class _Layout {
  const _Layout({
    required this.plot,
    required this.labelHeight,
    required this.series,
    required this.leftLabels,
    required this.rightLabels,
    required this.xLabels,
    required this.grid,
    required this.targets,
  });

  factory _Layout.of(Size size, SeriesChart chart, ChartText text) {
    ChartSeries? on(SeriesAxis axis) => chart.series
        .where((series) => series.axis == axis && series.ticks.isNotEmpty)
        .firstOrNull;
    final left = on(SeriesAxis.left);
    final right = on(SeriesAxis.right);
    double widest(ChartSeries? series) => series == null
        ? 0
        : series.ticks
              .map((tick) => text.measure(series.yLabel(tick)).width)
              .reduce(math.max);
    final xSizes = [
      text.measure(chart.xLabel(chart.xMin)),
      text.measure(chart.xLabel(chart.xMax)),
    ];
    final xWidth = xSizes.map((size) => size.width).reduce(math.max);
    final labelHeight = xSizes.map((size) => size.height).reduce(math.max);
    final leftWidth = widest(left);
    final rightWidth = widest(right);
    final plot = Rect.fromLTRB(
      left == null ? 0 : leftWidth + Gap.sm,
      labelHeight / 2,
      math.max(
        0,
        size.width - (right == null ? xWidth / 2 : rightWidth + Gap.sm),
      ),
      math.max(labelHeight / 2, size.height - labelHeight * 1.5 - Gap.sm),
    );
    double x(double value) => scale(
      value,
      domainMin: chart.xMin,
      domainMax: chart.xMax,
      rangeMin: plot.left,
      rangeMax: plot.right,
    );
    double Function(double) y(List<double> ticks) =>
        (value) => ticks.isEmpty
        ? plot.center.dy
        : scale(
            value,
            domainMin: ticks.first,
            domainMax: ticks.last,
            rangeMin: plot.bottom,
            rangeMax: plot.top,
          );
    final yFit = labelsThatFit(plot.height, labelHeight, gap: Gap.sm);
    List<_Label> labels(ChartSeries? series) => series == null
        ? const []
        : [
            for (final tick in thinTicks(series.ticks, yFit))
              (
                text: series.yLabel(tick),
                at: y(series.ticks)(tick),
                color: series.color,
              ),
          ];

    final barSeries = chart.series.where((series) => series.bars).toList();
    final span = x(chart.xMin + chart.barSpan) - x(chart.xMin);
    final barWidth = span * barShare / math.max(1, barSeries.length);
    final placed = <_Placed>[];
    final targets = <({double x, double at})>[];
    for (final series in chart.series) {
      final toY = y(series.ticks);
      final slot = barSeries.indexOf(series);
      // Bar series side by side, together centred in the span.
      final inset = (span - barWidth * barSeries.length) / 2 + barWidth * slot;
      final bars = [
        if (series.bars)
          for (final point in series.points)
            Rect.fromLTRB(
              x(point.x) + inset,
              math.min(plot.bottom, toY(math.max(0, point.y))),
              x(point.x) + inset + barWidth,
              plot.bottom,
            ),
      ];
      placed.add((
        color: series.color,
        line: [
          if (!series.bars)
            for (final point in series.points) Offset(x(point.x), toY(point.y)),
        ],
        bars: bars,
        guide: switch (series.guide) {
          final guide? => toY(guide),
          null => null,
        },
      ));
      for (final point in series.points) {
        targets.add((
          x: point.x,
          at: series.bars ? x(point.x) + span / 2 : x(point.x),
        ));
      }
    }
    final xFit = labelsThatFit(plot.width, xWidth, gap: Gap.sm);
    return _Layout(
      plot: plot,
      labelHeight: labelHeight,
      series: placed,
      leftLabels: labels(left),
      rightLabels: labels(right),
      xLabels: [
        for (final tick in spreadTicks(chart.xMin, chart.xMax, xFit))
          (text: chart.xLabel(tick), at: x(tick), color: null),
      ],
      grid: switch (left ?? chart.series.firstOrNull) {
        final series? => [
          for (final tick in thinTicks(series.ticks, yFit))
            y(series.ticks)(tick),
        ],
        null => const [],
      },
      targets: targets,
    );
  }

  final Rect plot;
  final double labelHeight;
  final List<_Placed> series;
  final List<_Label> leftLabels;
  final List<_Label> rightLabels;
  final List<_Label> xLabels;

  /// Where the grid lines go across.
  final List<double> grid;

  /// Every point's x and where across the plot it is picked.
  final List<({double x, double at})> targets;
}

class _Painter extends CustomPainter {
  _Painter({
    required this.layout,
    required this.text,
    required this.selectedAt,
    required this.grid,
  });

  final _Layout layout;
  final ChartText text;
  final double? selectedAt;
  final Color grid;

  static const _lineWidth = 2.0;
  static const _gridWidth = 1.0;
  static const _dotRadius = 3.0;
  static const _dash = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = layout.plot;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = _gridWidth;
    for (final at in layout.grid) {
      canvas.drawLine(Offset(plot.left, at), Offset(plot.right, at), gridPaint);
    }
    void label(_Label label, double Function(TextPainter) left, double top) {
      final painter = TextPainter(
        text: TextSpan(
          text: label.text,
          style: text.style?.copyWith(color: label.color),
        ),
        textDirection: text.direction,
        textScaler: text.scaler,
      )..layout();
      painter.paint(canvas, Offset(left(painter), top - painter.height / 2));
      painter.dispose();
    }

    for (final item in layout.leftLabels) {
      label(item, (painter) => plot.left - Gap.sm - painter.width, item.at);
    }
    for (final item in layout.rightLabels) {
      label(item, (_) => plot.right + Gap.sm, item.at);
    }
    final xTop =
        xLabelsTop(plot, layout.labelHeight, Gap.sm) + layout.labelHeight / 2;
    for (final item in layout.xLabels) {
      label(
        item,
        (painter) => math.max(
          0.0,
          math.min(item.at - painter.width / 2, size.width - painter.width),
        ),
        xTop,
      );
    }
    if (selectedAt case final x?) {
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }
    for (final series in layout.series) {
      final paint = Paint()..color = series.color;
      for (final bar in series.bars) {
        canvas.drawRect(bar, paint);
      }
    }
    for (final series in layout.series) {
      final stroke = Paint()
        ..color = series.color
        ..strokeWidth = _lineWidth
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      if (series.guide case final at?) {
        for (var x = plot.left; x < plot.right; x += _dash * 2) {
          canvas.drawLine(
            Offset(x, at),
            Offset(math.min(x + _dash, plot.right), at),
            stroke,
          );
        }
      }
      if (series.line.isEmpty) continue;
      canvas.drawPath(Path()..addPolygon(series.line, false), stroke);
      final dot = Paint()..color = series.color;
      for (final point in series.line) {
        canvas.drawCircle(point, _dotRadius, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}
