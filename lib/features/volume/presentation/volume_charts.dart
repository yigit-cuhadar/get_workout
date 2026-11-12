import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../domain/weekly_volume.dart';
import 'volume_text.dart';

// Small stand-ins until the progress charts are unified in forge_ui
// (SPEC.md, Decisions, "Volume charts").

/// The sets a chart reaches at least, so the band always shows with room
/// above it.
const _minScale = VolumeBand.max * 1.25;

/// The top of a scale holding every value of [sets].
double volumeScale(Iterable<double> sets) => sets.fold(_minScale, math.max);

/// One muscle's weekly sets as a bar over the [VolumeBand], on a scale up
/// to [scale].
class VolumeBandBar extends StatelessWidget {
  const VolumeBandBar({super.key, required this.sets, required this.scale});

  final double sets;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: Gap.sm,
      width: double.infinity,
      child: CustomPaint(
        painter: _BandBarPainter(
          sets: sets,
          scale: scale,
          track: colors.surfaceContainerHighest,
          band: colors.outline,
          bar: VolumeZone.of(sets).color(colors),
        ),
      ),
    );
  }
}

class _BandBarPainter extends CustomPainter {
  _BandBarPainter({
    required this.sets,
    required this.scale,
    required this.track,
    required this.band,
    required this.bar,
  });

  final double sets;
  final double scale;
  final Color track;
  final Color band;
  final Color bar;

  @override
  void paint(Canvas canvas, Size size) {
    double x(num value) => size.width * value / scale;
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = track)
      ..drawRect(
        Rect.fromLTRB(x(0), 0, x(math.min(sets, scale)), size.height),
        Paint()..color = bar,
      );
    final edge = Paint()
      ..color = band
      ..strokeWidth = size.height / 4;
    for (final end in [VolumeBand.min, VolumeBand.max]) {
      canvas.drawLine(
        Offset(x(end), -size.height / 2),
        Offset(x(end), size.height * 1.5),
        edge,
      );
    }
  }

  @override
  bool shouldRepaint(_BandBarPainter old) =>
      old.sets != sets ||
      old.scale != scale ||
      old.track != track ||
      old.band != band ||
      old.bar != bar;
}

/// Weekly sets as bars, oldest week first, with the [VolumeBand] shaded
/// behind them.
class VolumeTrendChart extends StatelessWidget {
  const VolumeTrendChart({
    super.key,
    required this.sets,
    required this.semanticLabel,
  });

  final List<double> sets;
  final String semanticLabel;

  /// Width to height of the chart.
  static const _aspectRatio = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: CustomPaint(
          painter: _TrendPainter(
            sets: sets,
            scale: volumeScale(sets),
            band: colors.surfaceContainerHighest,
            colors: colors,
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.sets,
    required this.scale,
    required this.band,
    required this.colors,
  });

  final List<double> sets;
  final double scale;
  final Color band;
  final ColorScheme colors;

  /// Share of each week's slot left empty between bars.
  static const _gap = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    double y(num value) => size.height * (1 - value / scale);
    canvas.drawRect(
      Rect.fromLTRB(0, y(VolumeBand.max), size.width, y(VolumeBand.min)),
      Paint()..color = band,
    );
    if (sets.isEmpty) return;
    final slot = size.width / sets.length;
    for (final (i, value) in sets.indexed) {
      if (value <= 0) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          slot * (i + _gap / 2),
          y(value),
          slot * (i + 1 - _gap / 2),
          size.height,
        ),
        Paint()..color = VolumeZone.of(value).color(colors),
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.sets != sets ||
      old.scale != scale ||
      old.band != band ||
      old.colors != colors;
}
