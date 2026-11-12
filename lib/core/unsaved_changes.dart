import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// A page whose unsaved changes a navigation could drop.
abstract interface class UnsavedPage {
  /// The page's path.
  String get location;

  bool get hasUnsavedChanges;

  /// Shows the page and asks whether to discard its changes; true when the
  /// user agreed, after which it has none.
  Future<bool> confirmDiscard();
}

/// The open pages with unsaved changes, so that a navigation which would
/// drop one asks first. Pages join through [UnsavedChangesGuard].
class UnsavedChanges {
  final _pages = <UnsavedPage>{};

  void add(UnsavedPage page) => _pages.add(page);

  void remove(UnsavedPage page) => _pages.remove(page);

  /// For [GoRouter.onEnter]. A `go` replaces the target tab's stack, so a
  /// page there with unsaved changes asks first, and the navigation is made
  /// again once it agrees. Push, a tab switch (restore) and a refresh drop no
  /// page; pops never come here, so a page's own back prompt is the only one.
  OnEnterResult onEnter(
    BuildContext context,
    GoRouterState current,
    GoRouterState next,
    GoRouter router,
  ) {
    final state = router.routeInformationProvider.value.state;
    final page =
        state is RouteInformationState && state.type == NavigatingType.go
        ? droppedBy(next.uri.path)
        : null;
    if (page == null) return const Allow();
    return Block.then(() async {
      if (await page.confirmDiscard()) {
        router.go(next.uri.toString(), extra: next.extra);
      }
    });
  }

  /// The first page with unsaved changes that going to [location] would drop.
  UnsavedPage? droppedBy(String location) => _pages
      .where((page) => page.hasUnsavedChanges && drops(location, page.location))
      .firstOrNull;

  /// Whether going to [target] drops the page at [page]. Each tab keeps its
  /// own stack under its first path segment; going into a tab replaces its
  /// stack with [target]'s pages, keeping those on the way to it.
  static bool drops(String target, String page) {
    String tab(String path) => Uri.parse(path).pathSegments.firstOrNull ?? '';
    return tab(target) == tab(page) &&
        target != page &&
        !target.startsWith('$page/');
  }
}

/// Registers its page with the [UnsavedChanges] above it while mounted. Its
/// back behaviour stays with the page's own `PopScope`.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.hasChanges,
    required this.confirmDiscard,
    required this.child,
  });

  /// Read at each navigation.
  final bool Function() hasChanges;

  /// The page's own discard prompt; true to discard.
  final Future<bool> Function() confirmDiscard;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard>
    implements UnsavedPage {
  late final UnsavedChanges _registry = context.read<UnsavedChanges>();
  String? _location;
  bool _discarded = false;

  /// The prompt on screen; a second navigation meanwhile waits for it.
  Future<bool>? _asking;

  @override
  String get location => _location!;

  @override
  bool get hasUnsavedChanges => !_discarded && widget.hasChanges();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_location == null) {
      _location = GoRouterState.of(context).matchedLocation;
      _registry.add(this);
    }
  }

  @override
  void dispose() {
    _registry.remove(this);
    super.dispose();
  }

  @override
  Future<bool> confirmDiscard() =>
      _asking ??= _ask().whenComplete(() => _asking = null);

  Future<bool> _ask() async {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      final navigator = Navigator.of(context);
      final tab = shell.route.branches.indexWhere(
        (branch) => branch.navigatorKey.currentState == navigator,
      );
      if (tab >= 0 && tab != shell.currentIndex) {
        shell.goBranch(tab);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (!mounted) return true;
    return _discarded = await widget.confirmDiscard();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
