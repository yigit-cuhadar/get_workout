import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:forge_ui/forge_ui.dart' show Gap;

/// Forge's earlier ruler, kept until the profile questions move to
/// `NumberPicker.ruler`, which drags at a different scale.
///
/// A horizontal ruler that picks a number from [min] to [max] in steps of
/// [step] by dragging it under a fixed pointer. Every fifth tick is longer
/// and every tenth longer still, counted from zero rather than from [min].
///
/// [onChanged] reports each step the user moves to, with the floating-point
/// noise of `min + n * step` rounded away. A new [value] from the parent
/// moves the ruler to the nearest tick without reporting it, so a value
/// between ticks stays as given until the user drags. It also ends a drag
/// under way, so the ruler never fights the finger for its position.
///
/// The last tick is the last step that does not pass [max].
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    super.key,
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.onChanged,
  });

  final double min;
  final double max;
  final double step;
  final double value;
  final ValueChanged<double> onChanged;

  static const tickSpacing = Gap.sm;
  static const _height = Gap.xl * 2;

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _index * RulerPicker.tickSpacing,
  );
  late int _index = _indexOf(widget.value);

  /// Set while the ruler follows a new [RulerPicker.value], whose scrolling
  /// is no pick of the user's.
  bool _following = false;

  // The epsilon keeps a last step that lands on max from rounding away.
  int get _count =>
      ((widget.max - widget.min) / widget.step + 1e-9).floor() + 1;

  /// As many decimals as [RulerPicker.step] has, so whole steps read
  /// without a trailing ".0".
  int get _decimals {
    var decimals = 0;
    while (decimals < 10) {
      final scaled = widget.step * math.pow(10, decimals);
      if ((scaled - scaled.round()).abs() < 1e-9) break;
      decimals++;
    }
    return decimals;
  }

  String _label(int index) =>
      _valueAt(index.clamp(0, _count - 1)).toStringAsFixed(_decimals);

  int _indexOf(double value) =>
      ((value - widget.min) / widget.step).round().clamp(0, _count - 1);

  double _valueAt(int index) =>
      double.parse((widget.min + index * widget.step).toStringAsFixed(10));

  @override
  void didUpdateWidget(RulerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _indexOf(widget.value);
    if (index == _index &&
        widget.min == oldWidget.min &&
        widget.step == oldWidget.step) {
      return;
    }
    _index = index;
    // After layout, when the ticks of a new range are in place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _following = true;
      _controller.jumpTo(_index * RulerPicker.tickSpacing);
      _following = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    if (_following) return false;
    final index = (notification.metrics.pixels / RulerPicker.tickSpacing)
        .round()
        .clamp(0, _count - 1);
    if (index != _index) {
      // Rebuilt for the semantics value.
      setState(() => _index = index);
      HapticFeedback.selectionClick();
      widget.onChanged(_valueAt(index));
    }
    return false;
  }

  /// Moves one tick by [delta] for assistive technologies.
  void _nudge(int delta) {
    final index = (_index + delta).clamp(0, _count - 1);
    if (index != _index) {
      _controller.jumpTo(index * RulerPicker.tickSpacing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Ticks from zero, so the long ones fall on round values.
    final first = (widget.min / widget.step).round();
    return Semantics(
      slider: true,
      value: _label(_index),
      increasedValue: _label(_index + 1),
      decreasedValue: _label(_index - 1),
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      child: SizedBox(
        height: RulerPicker._height,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              // The ticks say nothing the slider does not.
              ExcludeSemantics(
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: _onScroll,
                  child: ListView.builder(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    physics: const _SnapPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    // The first and last tick can reach the pointer.
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          (constraints.maxWidth - RulerPicker.tickSpacing) / 2,
                    ),
                    itemExtent: RulerPicker.tickSpacing,
                    itemCount: _count,
                    itemBuilder: (context, index) {
                      final tick = first + index;
                      return Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: 1,
                          height: tick % 10 == 0
                              ? Gap.xl
                              : tick % 5 == 0
                              ? Gap.lg
                              : Gap.md,
                          child: ColoredBox(color: colors.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ),
              IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: Gap.xs / 2,
                    height: Gap.xl + Gap.md,
                    child: ColoredBox(color: colors.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Comes to rest on a tick.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({super.parent});

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final fling = super.createBallisticSimulation(position, velocity);
    final end = fling?.x(double.infinity) ?? position.pixels;
    final target =
        ((end / RulerPicker.tickSpacing).round() * RulerPicker.tickSpacing)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    final tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}
