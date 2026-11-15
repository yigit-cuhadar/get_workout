import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'set_bubble.dart';

/// How an [ExerciseCard] shows its exercises.
enum ExerciseCardForm {
  /// Each exercise's name over a progress bar, its count and menu.
  collapsed,

  /// One card at a time: grown, with its goal, last time and note and the
  /// set bubbles, in an accent border.
  open,

  /// While the cards are reordered: each exercise on one short line.
  line,

  /// The card being dragged: its lines, lifted with a shadow.
  lifted,
}

/// The [SetBubble]s of an exercise in an open card: its [warmups], then its
/// [working] sets in order (one per round in a superset or circuit), then
/// the [add] bubble.
class ExerciseCardSets {
  const ExerciseCardSets({
    required this.warmups,
    required this.working,
    required this.add,
  });

  final List<Widget> warmups;
  final List<Widget> working;
  final Widget add;
}

/// One exercise of an [ExerciseCard].
class ExerciseCardItem {
  const ExerciseCardItem({
    required this.name,
    required this.count,
    required this.progress,
    required this.onOptions,
    this.allDone = false,
    this.letter,
    this.details = const [],
    this.sets,
    this.onTap,
  });

  final String name;

  /// Done of all its sets, e.g. `3/5`.
  final String count;

  /// The share of its sets done, from 0 to 1.
  final double progress;
  final bool allDone;

  /// Its place in a superset or circuit, e.g. `A1`.
  final String? letter;

  /// Shown open: its goal, last time and note, a line each.
  final List<String> details;

  /// Its bubbles, shown open.
  final ExerciseCardSets? sets;

  /// Opens its menu under the button whose context it is given.
  final ValueChanged<BuildContext> onOptions;
  final VoidCallback? onTap;
}

/// An exercise of the workout screen, or a superset or circuit of them
/// under its [group] label ("Superset A"). See [ExerciseCardForm].
///
/// [wrapLine] wraps each exercise's line, all of it but its menu, e.g. to
/// hold it for a drag.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.items,
    required this.optionsLabel,
    this.form = ExerciseCardForm.collapsed,
    this.group,
    this.wrapLine,
  });

  final List<ExerciseCardItem> items;

  /// What each item's menu button says to a screen reader.
  final String optionsLabel;
  final ExerciseCardForm form;
  final String? group;
  final Widget Function(int item, Widget line)? wrapLine;

  static const double _letterSize = 28;
  static const double _checkSize = 22;

  @override
  Widget build(BuildContext context) => switch (form) {
    ExerciseCardForm.collapsed => _frame(context, _collapsed(context)),
    ExerciseCardForm.open => _frame(context, _open(context), open: true),
    ExerciseCardForm.line => _frame(context, _lines(context)),
    ExerciseCardForm.lifted => Transform.scale(
      scale: 1.02,
      child: _frame(context, _lines(context), lifted: true),
    ),
  };

  Widget _frame(
    BuildContext context,
    Widget child, {
    bool open = false,
    bool lifted = false,
  }) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final radius = BorderRadius.circular(style.radii.lg);
    final border = open
        ? Border.all(color: colors.accent, width: 1.5)
        : lifted || style.cardBorder == 0
        ? null
        : Border.all(color: colors.line, width: style.cardBorder);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: border,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow
                      .withValues(alpha: 0.18),
                  offset: const Offset(0, 8),
                  blurRadius: 28,
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _wrap(int item, Widget line) => wrapLine?.call(item, line) ?? line;

  Widget _groupLabel(BuildContext context, EdgeInsets padding) => Padding(
    padding: padding,
    child: Text(
      group!,
      style: Theme.of(context).textTheme.labelMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: ForgeStyle.of(context).colors.accent,
      ),
    ),
  );

  Widget _collapsed(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group != null)
          _groupLabel(
            context,
            const EdgeInsets.fromLTRB(Gap.md, 10, Gap.md, 0),
          ),
        for (final (i, item) in items.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(top: BorderSide(color: colors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _wrap(
                    i,
                    InkWell(
                      onTap: item.onTap,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.fromLTRB(
                          Gap.md,
                          Gap.xs,
                          0,
                          Gap.xs,
                        ),
                        child: Row(
                          spacing: 10,
                          children: [
                            if (item.letter case final letter?)
                              _Letter(letter)
                            else if (item.allDone)
                              const _DoneCheck(),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 6,
                                children: [
                                  _name(context, item, muted: item.allDone),
                                  _Bar(item.progress),
                                ],
                              ),
                            ),
                            _count(context, item),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _Options(item: item, label: optionsLabel),
              ],
            ),
          ),
      ],
    );
  }

  Widget _open(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final grouped = group != null;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (grouped)
            _groupLabel(
              context,
              const EdgeInsets.symmetric(horizontal: Gap.md),
            ),
          for (final (i, item) in items.indexed)
            Row(
              children: [
                Expanded(
                  child: _wrap(
                    i,
                    InkWell(
                      onTap: item.onTap,
                      child: Padding(
                        padding: const EdgeInsets.only(left: Gap.md),
                        child: grouped
                            ? Row(
                                spacing: 10,
                                children: [
                                  if (item.letter case final letter?)
                                    _Letter(letter),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 1,
                                      children: [
                                        Text(
                                          item.name,
                                          style: text.titleMedium,
                                        ),
                                        for (final line in item.details)
                                          Text(
                                            line,
                                            style: text.labelMedium!.copyWith(
                                              fontWeight: FontWeight.w400,
                                              color: colors.inkMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                spacing: 10,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      spacing: 6,
                                      children: [
                                        Text(
                                          item.name,
                                          style: text.titleLarge!.copyWith(
                                            letterSpacing: -0.17,
                                          ),
                                        ),
                                        _Bar(item.progress),
                                      ],
                                    ),
                                  ),
                                  _count(context, item),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                _Options(item: item, label: optionsLabel),
              ],
            ),
          if (!grouped && items.single.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  for (final line in items.single.details)
                    Text(line, style: text.bodySmall),
                ],
              ),
            ),
          if (!grouped)
            if (items.single.sets case final sets?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [...sets.warmups, ...sets.working, sets.add],
                ),
              ),
          if (grouped && items.every((item) => item.sets != null))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, Gap.xs, Gap.md, 0),
              clipBehavior: Clip.none,
              child: _RoundGrid(
                letters: [for (final item in items) item.letter ?? ''],
                sets: [for (final item in items) item.sets!],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lines(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          _wrap(
            i,
            Container(
              height: ForgeTheme.tapMin,
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: colors.line)),
              ),
              child: Row(
                spacing: 10,
                children: [
                  if (item.letter case final letter?) _Letter(letter),
                  Expanded(child: _name(context, item)),
                  _count(context, item),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _name(
    BuildContext context,
    ExerciseCardItem item, {
    bool muted = false,
  }) {
    final colors = ForgeStyle.of(context).colors;
    return Text(
      item.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.w500,
        color: muted ? colors.inkMuted : colors.ink,
      ),
    );
  }

  Widget _count(BuildContext context, ExerciseCardItem item) {
    final style = ForgeStyle.of(context);
    return Text(
      item.count,
      style: style.data.copyWith(color: style.colors.inkMuted),
    );
  }
}

/// A 4px bar on surface-sunken, filled in accent to [value].
class _Bar extends StatelessWidget {
  const _Bar(this.value);

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final radius = BorderRadius.circular(2);
    return Container(
      height: 4,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: radius,
      ),
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.accent, borderRadius: radius),
        ),
      ),
    );
  }
}

/// An exercise's place in its group, e.g. `A1`, in a sunken circle.
class _Letter extends StatelessWidget {
  const _Letter(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return Container(
      width: ExerciseCard._letterSize,
      height: ExerciseCard._letterSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.colors.surfaceSunken,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: style.data.copyWith(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w500,
          color: style.colors.ink,
        ),
      ),
    );
  }
}

/// Every set done: a check in an accent circle.
class _DoneCheck extends StatelessWidget {
  const _DoneCheck();

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Container(
      width: ExerciseCard._checkSize,
      height: ExerciseCard._checkSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
      child: ForgeIcon(
        ForgeIcons.check,
        size: 14,
        weight: 3,
        color: colors.onAccent,
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.item, required this.label});

  final ExerciseCardItem item;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      onTap: () => item.onOptions(context),
      child: SizedBox.square(
        dimension: ForgeTheme.tapMin,
        child: Center(
          child: ForgeIcon(
            ForgeIcons.moreVert,
            size: 20,
            color: ForgeStyle.of(context).colors.inkMuted,
          ),
        ),
      ),
    ),
  );
}

/// The bubbles of an open superset or circuit: a row per exercise led by
/// its letter, its warm-ups first, then a column per round whose bubbles
/// are joined on a surface-sunken capsule, then its add bubble.
class _RoundGrid extends StatelessWidget {
  const _RoundGrid({required this.letters, required this.sets});

  final List<String> letters;
  final List<ExerciseCardSets> sets;

  static const double _labelWidth = 22;
  static const double _columnGap = 12;
  static const double _capsuleMargin = 4;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final size = SetBubble.sizeOf(context);
    final warmupSlots = sets.fold(
      0,
      (n, s) => s.warmups.length > n ? s.warmups.length : n,
    );
    final rounds = sets.fold(
      0,
      (n, s) => s.working.length > n ? s.working.length : n,
    );
    final columns = warmupSlots + rounds + 1;
    double x(int column) =>
        _labelWidth + _columnGap + column * (size + _columnGap);
    double y(int row) => row * (size + Gap.sm);
    final width = x(columns) - _columnGap;
    final height = y(sets.length) - Gap.sm;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var round = 0; round < rounds; round++)
            if (_rowsWith(round) case (final first, final last))
              Positioned(
                left: x(warmupSlots + round) - _capsuleMargin,
                top: y(first) - _capsuleMargin,
                width: size + 2 * _capsuleMargin,
                height: y(last) - y(first) + size + 2 * _capsuleMargin,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: style.colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(
                      size / 2 + _capsuleMargin,
                    ),
                  ),
                ),
              ),
          for (final (row, exercise) in sets.indexed) ...[
            Positioned(
              left: 0,
              top: y(row),
              width: _labelWidth,
              height: size,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  letters[row],
                  style: style.data.copyWith(
                    fontSize: 11,
                    color: style.colors.inkMuted,
                  ),
                ),
              ),
            ),
            for (final (slot, bubble) in exercise.warmups.indexed)
              Positioned(left: x(slot), top: y(row), child: bubble),
            for (final (round, bubble) in exercise.working.indexed)
              Positioned(
                left: x(warmupSlots + round),
                top: y(row),
                child: bubble,
              ),
            Positioned(
              left: x(warmupSlots + rounds),
              top: y(row),
              child: exercise.add,
            ),
          ],
        ],
      ),
    );
  }

  /// The first and last rows with a set in [round].
  (int, int)? _rowsWith(int round) {
    final rows = [
      for (final (row, exercise) in sets.indexed)
        if (round < exercise.working.length) row,
    ];
    return rows.isEmpty ? null : (rows.first, rows.last);
  }
}
