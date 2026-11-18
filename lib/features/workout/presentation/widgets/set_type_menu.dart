import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'set_bubble.dart';

/// A type a set can be, as a row of [SetTypeMenu]: its [label], and the
/// [bubble] label the set would get as it; the [current] type is ticked
/// instead.
class SetTypeMenuItem {
  const SetTypeMenuItem({
    required this.label,
    required this.bubble,
    required this.onTap,
    this.warmup = false,
    this.current = false,
  });

  final String label;
  final String bubble;
  final VoidCallback onTap;
  final bool warmup;
  final bool current;
}

/// Opens a [SetTypeMenu] beside the long-pressed bubble of [context]: under
/// it, left edges aligned, above it when there is no room below. A row
/// closes the menu, then runs; a tap outside closes it.
Future<void> showSetTypeMenu({
  required BuildContext context,
  required List<SetTypeMenuItem> types,
  required String removeLabel,
  required VoidCallback onRemove,
}) {
  final navigator = Navigator.of(context);
  final box = context.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  void close(VoidCallback run) {
    navigator.pop();
    run();
  }

  return navigator.push(
    _MenuRoute(
      anchor: anchor,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      menu: SetTypeMenu(
        types: [
          for (final type in types)
            SetTypeMenuItem(
              label: type.label,
              bubble: type.bubble,
              warmup: type.warmup,
              current: type.current,
              onTap: () => close(type.onTap),
            ),
        ],
        removeLabel: removeLabel,
        onRemove: () => close(onRemove),
      ),
    ),
  );
}

/// The menu a set bubble opens on a long press: the [types] the set can
/// be, the current one ticked and the others with the bubble they would
/// give, then [removeLabel] in danger, split by lines.
class SetTypeMenu extends StatelessWidget {
  const SetTypeMenu({
    super.key,
    required this.types,
    required this.removeLabel,
    required this.onRemove,
  });

  final List<SetTypeMenuItem> types;
  final String removeLabel;
  final VoidCallback onRemove;

  static const double width = 200;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final radius = BorderRadius.circular(style.radii.lg);
    Widget row(String label, Color color, VoidCallback onTap, Widget? end) =>
        InkWell(
          onTap: onTap,
          // At least 44px; taller as the text grows.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ForgeTheme.tapMin),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(color: color),
                    ),
                  ),
                  ?end,
                ],
              ),
            ),
          ),
        );
    final divider = Container(height: 1, color: colors.line);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: style.cardBorder == 0
            ? null
            : Border.all(color: colors.line, width: style.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.18),
            offset: const Offset(0, 8),
            blurRadius: 28,
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final type in types) ...[
                Semantics(
                  selected: type.current,
                  child: row(
                    type.label,
                    colors.ink,
                    type.onTap,
                    type.current
                        ? ForgeIcon(
                            ForgeIcons.check,
                            size: 14,
                            weight: 3,
                            color: colors.ink,
                          )
                        : ExcludeSemantics(
                            child: SetBubble(
                              label: type.bubble,
                              semanticLabel: type.bubble,
                              onTap: null,
                              warmup: type.warmup,
                              small: true,
                            ),
                          ),
                  ),
                ),
                divider,
              ],
              row(removeLabel, colors.danger, onRemove, null),
            ],
          ),
        ),
      ),
    );
  }
}

/// The [types] a set can be as rows of the set options sheet: each label
/// with the bubble it would give, the current one with an accent tick
/// instead, split by lines.
class SetTypeList extends StatelessWidget {
  const SetTypeList({super.key, required this.types});

  final List<SetTypeMenuItem> types;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, type) in types.indexed)
          Semantics(
            selected: type.current,
            button: true,
            child: InkWell(
              onTap: type.onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: ForgeTheme.tapMin),
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                decoration: i == 0
                    ? null
                    : BoxDecoration(
                        border: Border(top: BorderSide(color: colors.line)),
                      ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        type.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (type.current)
                      ForgeIcon(
                        ForgeIcons.check,
                        size: 18,
                        weight: 3,
                        color: colors.accent,
                      )
                    else
                      ExcludeSemantics(
                        child: SetBubble(
                          label: type.bubble,
                          semanticLabel: type.bubble,
                          onTap: null,
                          warmup: type.warmup,
                          small: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The bubble a type would give the set, small and pending.
class _MenuRoute extends PopupRoute<void> {
  _MenuRoute({
    required this.anchor,
    required this.menu,
    required this.barrierLabel,
  });

  final Rect anchor;
  final Widget menu;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(delegate: _BesideLayout(anchor), child: menu);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// Under [anchor] with left edges aligned, inside the screen's gutter;
/// above it when there is no room below.
class _BesideLayout extends SingleChildLayoutDelegate {
  _BesideLayout(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(Gap.md));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = anchor.left.clamp(Gap.md, size.width - Gap.md - child.width);
    final below = anchor.bottom + Gap.sm;
    final y = below + child.height <= size.height - Gap.md
        ? below
        : anchor.top - Gap.sm - child.height;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BesideLayout old) => old.anchor != anchor;
}

/// A kind of set the add bubble offers: its [label], the [bubble] the new
/// set would get and what it is in one line.
class AddSetOption {
  const AddSetOption({
    required this.label,
    required this.hint,
    required this.bubble,
    required this.onTap,
    this.warmup = false,
  });

  final String label;
  final String hint;
  final String bubble;
  final VoidCallback onTap;
  final bool warmup;
}

/// The add bubble's sheet: [title], the set types [tip] on top the first
/// time, then each of the [options] as a row with its bubble and one line.
class AddSetSheet extends StatelessWidget {
  const AddSetSheet({
    super.key,
    required this.title,
    required this.options,
    this.tip,
  });

  final String title;
  final List<AddSetOption> options;
  final Widget? tip;

  static const double _optionHeight = 64;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    return ForgeBottomSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tip case final tip?)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: tip),
          for (final option in options)
            InkWell(
              onTap: option.onTap,
              child: Container(
                // At least 64px; taller as the text grows.
                constraints: const BoxConstraints(minHeight: _optionHeight),
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: style.colors.line)),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    ExcludeSemantics(
                      child: SetBubble(
                        label: option.bubble,
                        semanticLabel: option.label,
                        warmup: option.warmup,
                        onTap: null,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 1,
                        children: [
                          Text(option.label, style: text.titleMedium),
                          Text(
                            option.hint,
                            style: text.labelMedium!.copyWith(
                              fontWeight: FontWeight.w400,
                              color: style.colors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
