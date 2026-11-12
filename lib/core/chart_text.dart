import 'package:flutter/material.dart';

/// How a chart's labels are written; measures and paints them.
class ChartText {
  const ChartText({
    required this.style,
    required this.direction,
    required this.scaler,
  });

  /// The labels of the theme, at the user's text size.
  factory ChartText.of(BuildContext context) {
    final theme = Theme.of(context);
    return ChartText(
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
    );
  }

  final TextStyle? style;
  final TextDirection direction;
  final TextScaler scaler;

  /// Laid out; the caller disposes it.
  TextPainter painter(String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout();

  Size measure(String text) {
    final painter = this.painter(text);
    final size = painter.size;
    painter.dispose();
    return size;
  }

  @override
  bool operator ==(Object other) =>
      other is ChartText &&
      other.style == style &&
      other.direction == direction &&
      other.scaler == scaler;

  @override
  int get hashCode => Object.hash(style, direction, scaler);
}
