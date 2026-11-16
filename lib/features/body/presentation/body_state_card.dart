import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// A page-level empty or error view of the body pages inside a card, as
/// their boards draw it, with [below] under the card.
class BodyStateCard extends StatelessWidget {
  const BodyStateCard(this.view, {super.key, this.below});

  /// An [EmptyView] or [ErrorView].
  final Widget view;
  final Widget? below;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Gap.md),
    children: [
      ListRowCard(children: [view]),
      if (below case final below?) ...[const SizedBox(height: 10), below],
    ],
  );
}
