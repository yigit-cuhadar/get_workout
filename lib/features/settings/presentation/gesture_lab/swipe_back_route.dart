import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A page with the iOS slide that a back swipe drags away, as Flutter's
/// Cupertino route does, with two differences: with [fullWidth] the swipe
/// starts anywhere on the page, as on native iOS, not only at the left
/// edge; and a page whose `PopScope` blocks popping still follows the
/// swipe, then springs back and asks it to pop, so its own prompt decides.
class SwipeBackRoute<T> extends MaterialPageRoute<T> {
  SwipeBackRoute({required super.builder, required this.fullWidth});

  final bool fullWidth;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      CupertinoPageTransition.delegatedTransition;

  AnimationController get _controller => controller!;

  bool get _canSwipe =>
      !isFirst &&
      isCurrent &&
      !willHandlePopInternally &&
      !navigator!.userGestureInProgress &&
      animation!.isCompleted &&
      secondaryAnimation!.isDismissed;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CupertinoPageTransition(
    primaryRouteAnimation: animation,
    secondaryRouteAnimation: secondaryAnimation,
    linearTransition: popGestureInProgress,
    child: _SwipeBackDetector(route: this, child: child),
  );
}

class _SwipeBackDetector extends StatefulWidget {
  const _SwipeBackDetector({required this.route, required this.child});

  final SwipeBackRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeBackDetector> createState() => _SwipeBackDetectorState();
}

class _SwipeBackDetectorState extends State<_SwipeBackDetector> {
  // Flutter's Cupertino route's values: the edge strip, a fling in screen
  // widths per second, and how long the page takes to settle.
  static const _edgeWidth = 20.0;
  static const _minFling = 1.0;
  static const _settle = Duration(milliseconds: 350);

  late final _drag = HorizontalDragGestureRecognizer(debugOwner: this)
    ..onStart = _start
    ..onUpdate = _update
    ..onEnd = _dragEnd
    ..onCancel = () => _end(0);
  bool _dragging = false;

  SwipeBackRoute<dynamic> get _route => widget.route;
  AnimationController get _controller => _route._controller;
  NavigatorState get _navigator => _route.navigator!;

  double get _direction =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  @override
  void dispose() {
    _drag.dispose();
    if (_dragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_navigator.mounted) _navigator.didStopUserGesture();
      });
    }
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (_route._canSwipe) _drag.addPointer(event);
  }

  void _start(DragStartDetails details) {
    _dragging = true;
    _navigator.didStartUserGesture();
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging) return;
    _controller.value -=
        _direction * details.primaryDelta! / context.size!.width;
  }

  void _dragEnd(DragEndDetails details) =>
      _end(details.velocity.pixelsPerSecond.dx);

  void _end(double velocityPx) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = _direction * velocityPx / context.size!.width;
    final leave = velocity.abs() >= _minFling
        ? velocity > 0
        : _controller.value < 0.5;
    const curve = Curves.fastEaseInToSlowEaseOut;
    final blocked = _route.popDisposition == RoutePopDisposition.doNotPop;
    if (leave && !blocked) {
      _navigator.pop();
      if (_controller.isAnimating) {
        _controller.animateBack(0, duration: _settle, curve: curve);
      }
    } else {
      _controller.animateTo(1, duration: _settle, curve: curve);
    }
    if (_controller.isAnimating) {
      void stop(AnimationStatus status) {
        if (status.isAnimating) return;
        _navigator.didStopUserGesture();
        _controller.removeStatusListener(stop);
      }

      _controller.addStatusListener(stop);
    } else {
      _navigator.didStopUserGesture();
    }
    // The page's PopScope hears the attempt and asks.
    if (leave && blocked) _navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_route.fullWidth) {
      return Listener(
        onPointerDown: _down,
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
    }
    // As Flutter's: wider on the side of a notch.
    final notch = Directionality.of(context) == TextDirection.rtl
        ? MediaQuery.paddingOf(context).right
        : MediaQuery.paddingOf(context).left;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          width: max(notch, _edgeWidth),
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _down,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
