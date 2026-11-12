import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The split of a slider [width] wide for a touch at [dx]: the share of the
/// width left of the bar, kept from 0 to 1.
double splitAt(double dx, double width) =>
    width <= 0 ? 0.5 : (dx / width).clamp(0.0, 1.0);

/// Two pictures in one place: [before] shows left of a vertical bar,
/// [after] right of it, and dragging or tapping moves the bar. Both are
/// laid out to the slider's whole size, so with the same fit the bar
/// reveals the same region of each. Give it a bounded size.
class BeforeAfterSlider extends StatefulWidget {
  const BeforeAfterSlider({
    super.key,
    required this.before,
    required this.after,
  });

  final Widget before;
  final Widget after;

  /// The bar, for finding it in tests.
  static const barKey = ValueKey('BeforeAfterSlider.bar');

  static const _barWidth = 2.0;
  static const _handleSize = Gap.xl;

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final x = width * _split;
        void move(Offset at) => setState(() => _split = splitAt(at.dx, width));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => move(details.localPosition),
          onHorizontalDragStart: (details) => move(details.localPosition),
          onHorizontalDragUpdate: (details) => move(details.localPosition),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.after,
              ClipRect(clipper: _LeftOf(_split), child: widget.before),
              Positioned(
                key: BeforeAfterSlider.barKey,
                left: x - BeforeAfterSlider._barWidth / 2,
                width: BeforeAfterSlider._barWidth,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: colors.primary),
              ),
              Positioned(
                left: x - BeforeAfterSlider._handleSize / 2,
                width: BeforeAfterSlider._handleSize,
                top: 0,
                bottom: 0,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: BeforeAfterSlider._handleSize,
                      child: Icon(
                        Icons.compare_arrows,
                        color: colors.onPrimary,
                        size: Gap.md,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The part left of [split] (a share of the width).
class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.split);
  final double split;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftOf oldClipper) => oldClipper.split != split;
}
