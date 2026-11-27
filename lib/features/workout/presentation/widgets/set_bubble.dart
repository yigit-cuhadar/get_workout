import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_ui/forge_ui.dart';

/// A warm-up's and a drop set's mark in a set bubble: the English initials
/// in every language, as lifters write them.
const warmupMark = 'W';
const dropMark = 'D';

/// One set as a circle with its [label] in mono: a done set filled in
/// accent, the current set (selected, not done) ringed 2.5px in accent, a
/// pending set ringed 1.5px in line-strong; a [warmup]'s ring is dashed. A
/// selected done set gets an accent ring 2.5px off it, dashed for a
/// warm-up. [SetBubble.add] ends a row of them. A [small] bubble (28px)
/// stands for a set in a line of text, such as a warm-up set's row or the
/// set table. [SetBubble.letter] is a superset's group letter: small, on
/// the sunken fill, no ring.
///
/// [actions], also offered by [onLongPress], reach screen readers as
/// custom actions.
class SetBubble extends StatelessWidget {
  const SetBubble({
    super.key,
    required String this.label,
    required this.semanticLabel,
    required this.onTap,
    this.done = false,
    this.selected = false,
    this.warmup = false,
    this.onLongPress,
    this.actions,
    this.small = false,
  }) : letter = false;

  /// The add bubble: the add icon on a pending ring.
  const SetBubble.add({
    super.key,
    required this.semanticLabel,
    required this.onTap,
  }) : label = null,
       done = false,
       selected = false,
       warmup = false,
       onLongPress = null,
       actions = null,
       small = false,
       letter = false;

  /// A group letter: no set, nothing to tap.
  const SetBubble.letter(String this.label, {super.key})
    : semanticLabel = label,
      onTap = null,
      done = false,
      selected = false,
      warmup = false,
      onLongPress = null,
      actions = null,
      small = true,
      letter = true;

  final String? label;
  final String semanticLabel;

  /// Null leaves it untappable, as a bubble that only shows a set.
  final VoidCallback? onTap;
  final bool done;
  final bool selected;
  final bool warmup;
  final VoidCallback? onLongPress;
  final Map<CustomSemanticsAction, VoidCallback>? actions;
  final bool small;
  final bool letter;

  static const double diameter = 48;
  static const double smallDiameter = 28;

  /// The side of a bubble, grown with the text scale so its label fits.
  static double sizeOf(BuildContext context, {bool small = false}) {
    final side = small ? smallDiameter : diameter;
    return math.max(side, MediaQuery.textScalerOf(context).scale(side));
  }

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final current = selected && !done;
    final size = sizeOf(context, small: small);
    final ring = done || letter
        ? null
        : current
        ? (colors.accent, 2.5)
        : (colors.lineStrong, 1.5);
    final labelStyle = style.data.copyWith(
      fontSize: small
          ? 11
          : current
          ? 15
          : 14,
      height: 1,
      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
      color: done
          ? colors.onAccent
          : current
          ? colors.accent
          : colors.ink,
    );
    final label = this.label;
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: semanticLabel,
      onTap: onTap,
      onLongPress: onLongPress,
      customSemanticsActions: actions,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: CustomPaint(
          size: Size.square(size),
          painter: _BubblePainter(
            fill: done
                ? colors.accent
                : letter
                ? colors.surfaceSunken
                : colors.surface,
            ring: ring?.$1,
            ringWidth: ring?.$2 ?? 0,
            outline: selected && done ? colors.accent : null,
            dashed: warmup,
          ),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: label == null
                  ? ForgeIcon(ForgeIcons.add, size: 18, color: colors.inkMuted)
                  : Text(label, style: labelStyle, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// The disc, its ring inside the edge, and the selected done set's ring
/// [_outlineGap] outside it.
class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.fill,
    required this.ring,
    required this.ringWidth,
    required this.outline,
    required this.dashed,
  });

  final Color fill;
  final Color? ring;
  final double ringWidth;
  final Color? outline;
  final bool dashed;

  static const double _outlineWidth = 2.5;
  static const double _outlineGap = 2.5;
  static const int _dashes = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = fill);
    if (ring case final ring?) {
      _circle(canvas, center, radius - ringWidth / 2, ring, ringWidth);
    }
    if (outline case final outline?) {
      _circle(
        canvas,
        center,
        radius + _outlineGap + _outlineWidth / 2,
        outline,
        _outlineWidth,
      );
    }
  }

  void _circle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (!dashed) return canvas.drawCircle(center, radius, paint);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const sweep = math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect, i * 2 * sweep, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill ||
      old.ring != ring ||
      old.ringWidth != ringWidth ||
      old.outline != outline ||
      old.dashed != dashed;
}
