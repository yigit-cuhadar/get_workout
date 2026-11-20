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
/// it, also from its primary scroll view's top, unless the page cannot pop.
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

  // A page that cannot pop (PopScope) cannot be dragged down either.
  @override
  bool get enableDrag => popDisposition != RoutePopDisposition.doNotPop;
}

/// A page that rises from the bottom over everything, full screen, and
/// goes back down when it closes; a drag down on its [DragToClose] part
/// closes it too. Pages pushed above it move it as the platform's pushed
/// pages move the page below.
class RisingPage<T> extends Page<T> {
  const RisingPage({super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _RisingRoute<T>(this);
}

class _RisingRoute<T> extends PageRoute<T> {
  _RisingRoute(RisingPage<T> page) : super(settings: page);

  RisingPage<T> get _page => settings as RisingPage<T>;

  AnimationController get _controller => controller!;

  // Cupertino's, as its full-screen dialog's.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  // Like the full-screen dialog it is: the page below stays where it is.
  @override
  bool get fullscreenDialog => true;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CupertinoFullscreenDialogTransition(
    primaryRouteAnimation: animation,
    secondaryRouteAnimation: kAlwaysDismissedAnimation,
    linearTransition: navigator!.userGestureInProgress,
    // Pages above move it as the platform moves a page below.
    child: Theme.of(context).pageTransitionsTheme.buildTransitions(
      this,
      context,
      kAlwaysCompleteAnimation,
      secondaryAnimation,
      child,
    ),
  );
}

/// The part of a [RisingPage] a drag down closes it by: the page follows
/// the finger and, let go far or fast enough, closes, else springs back. A
/// page that refuses to close springs back and is asked. Elsewhere it does
/// nothing.
class DragToClose extends StatefulWidget {
  const DragToClose({super.key, required this.child});

  final Widget child;

  @override
  State<DragToClose> createState() => _DragToCloseState();
}

class _DragToCloseState extends State<DragToClose> {
  // As the edge swipe's (_AskingSwipe): a fling in page heights per
  // second, and how long the page takes to settle.
  static const _minFling = 1.0;
  static const _settle = Duration(milliseconds: 350);

  /// The page being dragged.
  _RisingRoute<dynamic>? _route;

  @override
  void dispose() {
    final navigator = _route?.navigator;
    if (navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.didStopUserGesture();
      });
    }
    super.dispose();
  }

  void _start(DragStartDetails details) {
    final route = ModalRoute.of(context);
    if (route is! _RisingRoute ||
        !route.isCurrent ||
        route.willHandlePopInternally ||
        !route.animation!.isCompleted ||
        route.navigator!.userGestureInProgress) {
      return;
    }
    _route = route;
    route.navigator!.didStartUserGesture();
  }

  void _update(DragUpdateDetails details) {
    final route = _route;
    if (route == null) return;
    final height = MediaQuery.sizeOf(context).height;
    route._controller.value -= details.primaryDelta! / height;
  }

  void _end(DragEndDetails details) =>
      _finish(details.velocity.pixelsPerSecond.dy);

  void _cancel() => _finish(0);

  void _finish(double velocityPx) {
    final route = _route;
    if (route == null) return;
    _route = null;
    final controller = route._controller;
    final navigator = route.navigator!;
    final velocity = velocityPx / MediaQuery.sizeOf(context).height;
    final close = velocity.abs() >= _minFling
        ? velocity > 0
        : controller.value < 0.5;
    if (close && route.popDisposition != RoutePopDisposition.doNotPop) {
      navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(
          0,
          duration: _settle,
          curve: Curves.fastEaseInToSlowEaseOut,
        );
      }
    } else {
      controller.animateTo(
        1,
        duration: _settle,
        curve: Curves.fastEaseInToSlowEaseOut,
      );
      // The page's PopScope hears the attempt and asks.
      if (close) navigator.maybePop();
    }
    if (controller.isAnimating) {
      void stop(AnimationStatus status) {
        if (status.isAnimating) return;
        controller.removeStatusListener(stop);
        navigator.didStopUserGesture();
      }

      controller.addStatusListener(stop);
    } else {
      navigator.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onVerticalDragStart: _start,
    onVerticalDragUpdate: _update,
    onVerticalDragEnd: _end,
    onVerticalDragCancel: _cancel,
    child: widget.child,
  );
}
