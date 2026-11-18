import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A pushed page on the platform's route: on iOS the Cupertino slide, which
/// a swipe from the left edge takes back. A page whose `PopScope` blocks
/// popping (unsaved changes) still follows that swipe: let go where it
/// would leave, it springs back and asks to pop, so the page's own prompt
/// decides.
class AppPage<T> extends MaterialPage<T> {
  const AppPage({super.key, required super.child, super.fullscreenDialog});

  @override
  Route<T> createRoute(BuildContext context) => _AppPageRoute<T>(this);
}

class _AppPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _AppPageRoute(AppPage<T> page) : super(settings: page);

  AppPage<T> get _page => settings as AppPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  // A sheet passes for a full-screen dialog (see SheetPage); this page
  // still steps back behind it.
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is CupertinoSheetRoute || super.canTransitionTo(nextRoute);

  AnimationController get _controller => controller!;

  /// Whether a swipe from the edge now asks the page to pop: the cases
  /// Flutter's own swipe handles, except that the page refuses to pop.
  bool get _swipeAsks =>
      isCurrent &&
      !isFirst &&
      !willHandlePopInternally &&
      popDisposition == RoutePopDisposition.doNotPop &&
      !navigator!.userGestureInProgress &&
      animation!.isCompleted &&
      secondaryAnimation!.isDismissed;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
    final theme = Theme.of(context);
    final cupertino =
        theme.pageTransitionsTheme.builders[theme.platform]
            is CupertinoPageTransitionsBuilder;
    if (fullscreenDialog || !cupertino) return transition;
    return _AskingSwipe(route: this, child: transition);
  }
}

/// The edge swipe of a page that refuses to pop, as Flutter's Cupertino
/// swipe moves the page, which springs back when let go.
class _AskingSwipe extends StatefulWidget {
  const _AskingSwipe({required this.route, required this.child});

  final _AppPageRoute<dynamic> route;
  final Widget child;

  @override
  State<_AskingSwipe> createState() => _AskingSwipeState();
}

class _AskingSwipeState extends State<_AskingSwipe> {
  // Flutter's Cupertino swipe's values: the edge strip, a fling in page
  // widths per second, and how long the page takes to settle.
  static const _edgeWidth = 20.0;
  static const _minFling = 1.0;
  static const _settle = Duration(milliseconds: 350);

  late final _drag = HorizontalDragGestureRecognizer(debugOwner: this)
    ..onStart = _start
    ..onUpdate = _update
    ..onEnd = _dragEnd
    ..onCancel = _cancel;
  bool _dragging = false;

  AnimationController get _controller => widget.route._controller;
  NavigatorState get _navigator => widget.route.navigator!;
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void dispose() {
    _drag.dispose();
    if (_dragging) {
      final navigator = _navigator;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.didStopUserGesture();
      });
    }
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (!widget.route._swipeAsks) return;
    final padding = MediaQuery.paddingOf(context);
    // As Flutter's: wider on the side of a notch.
    final edge = max(_rtl ? padding.right : padding.left, _edgeWidth);
    final x = event.localPosition.dx;
    final fromStart = _rtl ? context.size!.width - x : x;
    if (fromStart <= edge) _drag.addPointer(event);
  }

  void _start(DragStartDetails details) {
    _dragging = true;
    _navigator.didStartUserGesture();
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging) return;
    final delta = details.primaryDelta! / context.size!.width;
    _controller.value -= _rtl ? -delta : delta;
  }

  void _dragEnd(DragEndDetails details) =>
      _end(details.velocity.pixelsPerSecond.dx);

  void _cancel() => _end(0);

  void _end(double velocityPx) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = (_rtl ? -velocityPx : velocityPx) / context.size!.width;
    final leave = velocity.abs() >= _minFling
        ? velocity > 0
        : _controller.value < 0.5;
    final navigator = _navigator;
    _controller.animateTo(
      1,
      duration: _settle,
      curve: Curves.fastEaseInToSlowEaseOut,
    );
    if (_controller.isAnimating) {
      void stop(AnimationStatus status) {
        if (status.isAnimating) return;
        _controller.removeStatusListener(stop);
        navigator.didStopUserGesture();
      }

      _controller.addStatusListener(stop);
    } else {
      navigator.didStopUserGesture();
    }
    // The page's PopScope hears the attempt and asks.
    if (leave) navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    behavior: HitTestBehavior.translucent,
    child: widget.child,
  );
}

/// A page opened over the flow as an iOS sheet: dragging it down closes
/// it, also from its primary scroll view's top.
class SheetPage<T> extends Page<T> {
  const SheetPage({super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _SheetRoute<T>(this);
}

class _SheetRoute<T> extends CupertinoSheetRoute<T> {
  _SheetRoute(SheetPage<T> page)
    : super(settings: page, scrollableBuilder: _content);

  static Widget _content(BuildContext context, ScrollController controller) =>
      PrimaryScrollController(
        controller: controller,
        child: (ModalRoute.settingsOf(context)! as SheetPage<dynamic>).child,
      );

  // So its ForgeAppBar shows close, as on the full-screen dialog this
  // sheet is elsewhere. A page below steps back still: AppPage allows it,
  // go_router's own pages always do.
  @override
  bool get fullscreenDialog => true;
}
