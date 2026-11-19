import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The plain Forge card a page puts its own content in (a state view, a
/// ring): surface, radius-lg and the preset's card border.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.colors.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: style.colors.line, width: style.cardBorder),
      ),
      child: Padding(padding: const EdgeInsets.all(Gap.md), child: child),
    );
  }
}
