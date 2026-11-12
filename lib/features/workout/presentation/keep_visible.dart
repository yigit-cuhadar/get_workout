import 'package:flutter/widgets.dart';

import 'set_bar.dart';

/// Scrolls [child], the selected set, into view when it first shows (it is
/// built anew whenever the selection changes), and as the window's metrics
/// change (the keyboard opening) while a field of the [SetBar] has focus;
/// another field opening the keyboard is left to scroll to itself.
class KeepVisible extends StatefulWidget {
  const KeepVisible({super.key, required this.child});

  final Widget child;

  @override
  State<KeepVisible> createState() => _KeepVisibleState();
}

class _KeepVisibleState extends State<KeepVisible> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reveal();
  }

  @override
  void didChangeMetrics() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<SetBar>() != null) _reveal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// After layout; scrolls only as far as needed, in either direction.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    for (final policy in [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      Scrollable.ensureVisible(context, alignmentPolicy: policy);
    }
  });

  @override
  Widget build(BuildContext context) => widget.child;
}
