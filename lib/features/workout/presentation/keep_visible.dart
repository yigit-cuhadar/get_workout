import 'package:flutter/widgets.dart';

/// Scrolls [child] into view when it first shows, e.g. once selected, and
/// whenever the window's metrics change, e.g. as the keyboard opens.
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
  void didChangeMetrics() => _reveal();

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
