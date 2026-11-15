import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// A small line through [values], oldest first, spread evenly across, with
/// no axes or labels: the shape of a trend whose numbers show elsewhere.
/// Decorative, so screen readers skip it.
// Belongs in forge_ui; move it there when that package next changes.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: Gap.xl,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  static const _strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final span = high - low;
    // Inset so the stroke is never cut at the edges.
    const inset = _strokeWidth / 2;
    final height = size.height - _strokeWidth;
    final step = (size.width - _strokeWidth) / (values.length - 1);
    final points = [
      for (final (i, value) in values.indexed)
        Offset(
          inset + i * step,
          // A flat trend runs through the middle.
          inset + (span == 0 ? height / 2 : (high - value) / span * height),
        ),
    ];
    canvas.drawPoints(
      PointMode.polygon,
      points,
      Paint()
        ..color = color
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !listEquals(old.values, values);
}

/// Where a [Sparkline] will be once there are two values: a 44px box in a
/// 1px dashed line-strong outline with the [message] centred in it.
class SparklineEmpty extends StatelessWidget {
  const SparklineEmpty({super.key, required this.message});

  final String message;

  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return CustomPaint(
      painter: _DashedBoxPainter(colors.lineStrong),
      child: SizedBox(
        height: _height,
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: colors.inkMuted, fontWeight: FontWeight.w400),
          ),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  _DashedBoxPainter(this.color);

  final Color color;

  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(ForgeRadii.button),
        ),
      );
    final dashed = Path();
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        dashed.addPath(metric.extractPath(at, at + _dash), Offset.zero);
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) => old.color != color;
}
