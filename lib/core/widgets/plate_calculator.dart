import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';

/// One plate size on each side of the bar: its weight in kg ([kg], which
/// sizes its drawing), as shown with its unit ([weight], "25 kg") and
/// without ([short], "25"), and how many of it go on each side ([count]).
class PlateStack {
  const PlateStack({
    required this.kg,
    required this.weight,
    required this.short,
    required this.count,
  });

  final double kg;
  final String weight;
  final String short;
  final int count;
}

/// What to load on the bar, heaviest plates first.
///
/// The calculator's card has the [target] and the [bar] on top, one side
/// of the bar drawn side-on with plates sized by weight, then the [plates]
/// with their count and the load on each side ([perSide]).
/// [PlateCalculator.closest] is the card when the plates can't make the
/// [target]: the [closest] load below it, why, and its plates.
/// [PlateCalculator.compact] is the small box over the set panel: the
/// [target], the load per side, the plates as tags and the [bar].
/// Plates differ by size and tone, never by hue.
class PlateCalculator extends StatelessWidget {
  const PlateCalculator({
    super.key,
    required this.target,
    required String this.bar,
    required this.plates,
    required String this.perSide,
  }) : closest = null,
       _compact = false;

  const PlateCalculator.closest({
    super.key,
    required this.target,
    required String this.closest,
    required this.plates,
  }) : bar = null,
       perSide = null,
       _compact = false;

  const PlateCalculator.compact({
    super.key,
    required this.target,
    required String this.bar,
    required this.plates,
    required String this.perSide,
  }) : closest = null,
       _compact = true;

  final String target;
  final String? bar;
  final List<PlateStack> plates;
  final String? perSide;
  final String? closest;
  final bool _compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final caption = text.labelMedium!.copyWith(
      fontWeight: FontWeight.w400,
      color: colors.inkMuted,
    );
    final big = style.dataLg.copyWith(
      fontSize: 24,
      height: 1.2,
      color: colors.ink,
    );
    final closest = this.closest;
    if (_compact) {
      return _Card(
        padding: const EdgeInsets.all(14),
        spacing: 6,
        children: [
          Text(
            l10n.plateCalculatorCompact(target, perSide!),
            style: text.bodySmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final plate in plates)
                for (var i = 0; i < plate.count; i++) ForgeTag(plate.short),
              Text(l10n.plateCalculatorOnBar(bar!), style: caption),
            ],
          ),
        ],
      );
    }
    if (closest != null) {
      return _Card(
        padding: const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, Gap.md),
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: l10n.plateCalculatorTarget,
                  value: Text(target, style: big),
                ),
              ),
              _Figure(
                label: l10n.plateCalculatorClosest,
                value: Text(closest, style: big),
                end: true,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.sm,
            children: [
              ForgeIcon(ForgeIcons.info, size: 18, color: colors.inkMuted),
              Expanded(
                child: Text(
                  l10n.plateCalculatorCannotMake(target, closest),
                  style: text.bodySmall!.copyWith(color: colors.inkMuted),
                ),
              ),
            ],
          ),
          for (final plate in plates)
            _PlateRow(
              plate: plate,
              height: 34,
              style: style.data.copyWith(fontSize: 14, color: colors.ink),
            ),
        ],
      );
    }
    final rowStyle = style.data.copyWith(fontSize: 15, color: colors.ink);
    final divider = Container(height: 1, color: colors.line);
    return _Card(
      padding: const EdgeInsets.all(14),
      spacing: 10,
      children: [
        Row(
          children: [
            Expanded(
              child: _Figure(
                label: l10n.plateCalculatorTarget,
                value: Text(target, style: big),
              ),
            ),
            _Figure(
              label: l10n.calcBar,
              value: Text(bar!, style: rowStyle),
              end: true,
            ),
          ],
        ),
        AspectRatio(
          aspectRatio: _BarPainter.width / _BarPainter.height,
          child: CustomPaint(
            painter: _BarPainter(
              plates: plates,
              colors: colors,
              label: style.data.copyWith(fontSize: 10, color: colors.inkMuted),
            ),
          ),
        ),
        divider,
        Text(
          l10n.plateCalculatorHeaviestFirst,
          style: text.labelSmall!.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.inkMuted,
          ),
        ),
        for (final plate in plates)
          _PlateRow(plate: plate, height: 36, style: rowStyle),
        divider,
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.plateCalculatorEachSide,
                style: text.bodySmall!.copyWith(color: colors.inkMuted),
              ),
            ),
            Text(perSide!, style: rowStyle),
          ],
        ),
      ],
    );
  }
}

/// How a plate of [kg] is drawn: the heavier, the wider, taller and
/// darker.
({double width, double height, Color tone}) _plateLook(
  double kg,
  ForgePalette colors,
) => switch (kg) {
  >= 20 => (width: 16, height: 120, tone: colors.ink),
  >= 10 => (width: 12, height: 84, tone: colors.inkMuted),
  >= 2.5 => (width: 8, height: 60, tone: colors.lineStrong),
  _ => (width: 6, height: 44, tone: colors.lineStrong),
};

class _Card extends StatelessWidget {
  const _Card({
    required this.padding,
    required this.spacing,
    required this.children,
  });

  final EdgeInsets padding;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: style.colors.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: style.colors.line, width: style.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: children,
      ),
    );
  }
}

/// A caption over its [value], right-aligned at the [end].
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.end = false});

  final String label;
  final Widget value;
  final bool end;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          fontWeight: FontWeight.w400,
          color: ForgeStyle.of(context).colors.inkMuted,
        ),
      ),
      value,
    ],
  );
}

/// A plate size: its swatch, weight and count per side.
class _PlateRow extends StatelessWidget {
  const _PlateRow({
    required this.plate,
    required this.height,
    required this.style,
  });

  final PlateStack plate;
  final double height;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final look = _plateLook(plate.kg, ForgeStyle.of(context).colors);
    return SizedBox(
      height: height,
      child: Row(
        spacing: 10,
        children: [
          Container(
            width: look.width,
            height: 22,
            decoration: BoxDecoration(
              color: look.tone,
              borderRadius: const BorderRadius.all(Radius.circular(3)),
            ),
          ),
          Expanded(child: Text(plate.weight, style: style)),
          Text(
            AppLocalizations.of(context).plateCalculatorCount(plate.count),
            style: style,
          ),
        ],
      ),
    );
  }
}

/// One side of the bar, side-on: the collar, the sleeve, and each plate
/// from the collar out with its weight under it; a label with no room
/// next to the one before drops a line, on a short leader.
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.plates,
    required this.colors,
    required this.label,
  });

  final List<PlateStack> plates;
  final ForgePalette colors;
  final TextStyle label;

  static const width = 280.0;
  static const height = 174.0;
  static const _axis = 70.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / width);
    void rect(double x, double y, double w, double h, double r, Color color) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(r),
          ),
          Paint()..color = color,
        );
    rect(0, 66, 40, 8, 2, colors.lineStrong);
    rect(36, 56, 8, 28, 2, colors.lineStrong);
    rect(44, 66, 230, 8, 2, colors.surfaceSunken);
    var x = 48.0;
    var labelEnd = double.negativeInfinity;
    for (final plate in plates) {
      final look = _plateLook(plate.kg, colors);
      for (var i = 0; i < plate.count; i++) {
        rect(x, _axis - look.height / 2, look.width, look.height, 3, look.tone);
        final centre = x + look.width / 2;
        final painter = TextPainter(
          text: TextSpan(text: plate.short, style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        final left = centre - painter.width / 2;
        final dropped = left < labelEnd + _gap;
        if (dropped) {
          canvas.drawLine(
            Offset(centre, 136),
            Offset(centre, 156),
            Paint()
              ..color = colors.line
              ..strokeWidth = 1,
          );
        } else {
          labelEnd = left + painter.width;
        }
        painter.paint(
          canvas,
          Offset(left, (dropped ? 167 : 150) - painter.height * 0.8),
        );
        painter.dispose();
        x += look.width + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) =>
      oldDelegate.plates != plates ||
      oldDelegate.colors != colors ||
      oldDelegate.label != label;
}
