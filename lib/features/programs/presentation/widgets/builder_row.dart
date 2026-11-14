import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';

/// One value chip of a [BuilderRow]: what it is ([label]: Sets, Reps, Time,
/// Rest) and its [value] in mono; a tap ([onTap]) edits it.
class BuilderValue {
  const BuilderValue({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
}

/// An exercise of a program day in the builder: a drag handle, the
/// exercise's [name], its [values] as chips, each editable on tap, and the
/// ⋯ [menu]. Rows sit in one card ([BuilderCard]); every row after the
/// first has a line above it ([divided]).
///
/// A row of a superset or circuit ([grouped]) carries the group's 3px
/// accent rule and accent-soft fill; the group's first row has the
/// [groupHeader] above it ("Superset · rest after both 1:30"). While it is
/// dragged ([lifted]) it floats on a soft shadow. [issues] say what is
/// wrong with it, in danger under its chips.
class BuilderRow extends StatelessWidget {
  const BuilderRow({
    super.key,
    required this.index,
    required this.name,
    required this.values,
    required this.menu,
    this.divided = true,
    this.grouped = false,
    this.groupHeader,
    this.lifted = false,
    this.issues = const [],
  });

  /// Its place in the reorderable list, for the drag handle.
  final int index;
  final String name;
  final List<BuilderValue> values;
  final List<ForgeMenuItem> menu;
  final bool divided;
  final bool grouped;
  final String? groupHeader;
  final bool lifted;
  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final groupHeader = this.groupHeader;
    final row = Container(
      // The chips' tap band takes the bottom padding but its last 2px.
      padding: const EdgeInsets.fromLTRB(10, 12, 12, 12 - _ValueChip.band),
      decoration: BoxDecoration(
        color: lifted ? colors.surface : null,
        borderRadius: lifted ? BorderRadius.circular(style.radii.lg) : null,
        border: divided && !lifted
            ? Border(top: BorderSide(color: colors.line))
            : null,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: colors.ink.withValues(alpha: 0.14),
                  offset: const Offset(0, 8),
                  blurRadius: 24,
                ),
              ]
            : null,
      ),
      child: Row(
        spacing: 10,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: l10n.programReorder,
              child: ForgeIcon(
                ForgeIcons.dragIndicator,
                size: 16,
                color: colors.lineStrong,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                Wrap(
                  spacing: 6,
                  children: [for (final value in values) _ValueChip(value)],
                ),
                for (final issue in issues)
                  Text(
                    issue,
                    style: text.bodySmall!.copyWith(color: colors.danger),
                  ),
              ],
            ),
          ),
          Builder(
            builder: (context) => Semantics(
              button: true,
              label: l10n.programItemActions,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showForgeMenu(context: context, items: menu),
                child: SizedBox(
                  width: Gap.lg,
                  height: ForgeTheme.tapMin,
                  child: Center(
                    child: ForgeIcon(
                      ForgeIcons.moreHoriz,
                      size: 18,
                      color: colors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final scaled = lifted ? Transform.scale(scale: 1.02, child: row) : row;
    if (!grouped) return scaled;
    return Container(
      decoration: BoxDecoration(
        color: colors.accentSoft,
        border: Border(left: BorderSide(color: colors.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groupHeader != null)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: Gap.sm),
              child: Text(
                groupHeader,
                style: text.labelSmall!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.inkMuted,
                ),
              ),
            ),
          scaled,
        ],
      ),
    );
  }
}

/// A value chip drawn 24px tall that takes taps across a 44px band, as
/// Forge's controls do.
class _ValueChip extends StatelessWidget {
  const _ValueChip(this.value);

  final BuilderValue value;

  static const double height = 24;
  static const double band = (ForgeTheme.tapMin - height) / 2;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: value.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: band),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Gap.xs,
              children: [
                Text(
                  value.label,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.inkMuted,
                  ),
                ),
                Text(
                  value.value,
                  style: style.data.copyWith(color: colors.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one card the [BuilderRow]s of a day sit in, around their [sliver].
class BuilderCard extends StatelessWidget {
  const BuilderCard({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: style.colors.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: style.colors.line, width: style.cardBorder),
      ),
      sliver: sliver,
    );
  }
}
