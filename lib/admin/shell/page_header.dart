import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The top of a panel page: an optional link back to its list, the
/// [title] over a muted [subtitle], and [trailing] (tags, the page's main
/// button) at the right.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.back,
    this.trailing = const [],
  });

  final String title;
  final String subtitle;

  /// The list this page belongs to, as its label and what opens it.
  final (String label, VoidCallback open)? back;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = ForgeStyle.of(context).colors.inkMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (back case (final label, final open))
          TextButton.icon(
            onPressed: open,
            icon: const Icon(Icons.arrow_back),
            label: Text(label),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.xs,
                children: [
                  Text(title, style: text.headlineSmall),
                  Text(
                    subtitle,
                    style: text.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ],
    );
  }
}
