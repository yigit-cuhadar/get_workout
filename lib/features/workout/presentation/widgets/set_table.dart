import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import 'set_bubble.dart';

/// One logged set of a [SetTable]: its bubble's [label] (W, 1, 4D…), its
/// [values] as done ("80 kg × 8", "45 s"), its [effort] as the effort
/// setting words it ("RIR 2", "Hard"; null shows "—"), whether it set a
/// [record], its [note], and its [drops] ("60 kg × 8"), each on a row of
/// its own under it.
class SetTableRow {
  const SetTableRow({
    required this.label,
    required this.values,
    this.effort,
    this.record = false,
    this.note,
    this.drops = const [],
  });

  final String label;
  final String values;
  final String? effort;
  final bool record;
  final String? note;
  final List<String> drops;
}

/// One value box of a [SetTableEditRow]: what it holds ([label], read out
/// by screen readers) and the [controller] it edits; a [wide] box holds a
/// weight.
class SetTableInput {
  const SetTableInput({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.wide = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool wide;
}

/// One set of a [SetTable.edit]: its bubble's [label], ticked ([done],
/// filled accent) or not (an outline), its values in small boxes joined by
/// "×" ([inputs]), and its [effort]. Tapping the bubble calls [onToggle],
/// holding it [onOptions] (with the bubble's context, to open a menu at
/// it), tapping the effort [onEffort] (null: not rated, as a warm-up or a
/// set not ticked). A drop set's [drops] follow in boxes of their own, then
/// its [note].
class SetTableEditRow {
  const SetTableEditRow({
    required this.label,
    required this.semanticLabel,
    required this.inputs,
    required this.done,
    required this.onToggle,
    required this.onOptions,
    this.effort,
    this.onEffort,
    this.drops = const [],
    this.note,
  });

  final String label;

  /// What screen readers call the bubble ("Set 2, done").
  final String semanticLabel;
  final List<SetTableInput> inputs;
  final bool done;
  final VoidCallback onToggle;
  final ValueChanged<BuildContext> onOptions;
  final String? effort;
  final VoidCallback? onEffort;
  final List<List<SetTableInput>> drops;
  final String? note;
}

/// The sets of an exercise in history, on a card: the exercise's [name],
/// its [group] letter (A1) in a sunken circle before it, its logging
/// [type] and [note] under it, its set [count] at the end, then a row per
/// set (see [SetTableRow]). With [onToggle] the header opens and closes
/// the card (a chevron down while closed, up while [open]); closed, only
/// the header shows.
///
/// [SetTable.edit] (Add past workout, Edit workout) has the exercise's ⋯
/// [menu] on top, the values in small boxes and "Add set" ([onAddSet]) at
/// the end.
class SetTable extends StatelessWidget {
  const SetTable({
    super.key,
    required this.name,
    required List<SetTableRow> this.rows,
    this.group,
    this.type,
    this.note,
    this.count,
    this.open = true,
    this.onToggle,
  }) : editRows = null,
       menu = null,
       onAddSet = null;

  /// [onAddSet] null: the exercise has as many sets as it may.
  const SetTable.edit({
    super.key,
    required this.name,
    required List<SetTableEditRow> rows,
    required List<ForgeMenuItem> this.menu,
    required this.onAddSet,
    this.group,
    this.note,
  }) : rows = null,
       editRows = rows,
       type = null,
       count = null,
       open = true,
       onToggle = null;

  final String name;
  final List<SetTableRow>? rows;
  final List<SetTableEditRow>? editRows;
  final String? group;
  final String? type;
  final String? note;
  final List<ForgeMenuItem>? menu;
  final VoidCallback? onAddSet;

  /// The set count at the header's end ("5 sets").
  final String? count;
  final bool open;
  final VoidCallback? onToggle;

  /// Where a set's drops and note start: past its bubble and the gap.
  static const _indent = SetBubble.smallDiameter + 10;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final editRows = this.editRows;
    final decoration = BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(style.radii.lg),
      border: style.cardBorder == 0
          ? null
          : Border.all(color: colors.line, width: style.cardBorder),
    );
    if (editRows != null) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.fromLTRB(14, Gap.xs, 14, Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EditHeader(name: name, group: group, note: note, menu: menu!),
            for (final (i, row) in editRows.indexed) ...[
              _EditRow(row: row, divided: i > 0),
              for (final (d, drop) in row.drops.indexed)
                _EditDropRow(inputs: drop, number: d + 1),
              if (row.note case final note?) _SetNote(note),
            ],
            if (onAddSet case final onAddSet?) _AddSet(onPressed: onAddSet),
          ],
        ),
      );
    }
    return Container(
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            name: name,
            group: group,
            type: type,
            note: note,
            count: count,
            open: open,
            onToggle: onToggle,
          ),
          if (open)
            for (final row in rows!) ...[
              _Row(row: row),
              if (row.note case final note?) _SetNote(note),
              for (final (d, drop) in row.drops.indexed)
                _DropRow(values: drop, number: d + 1),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.group,
    required this.type,
    required this.note,
    required this.count,
    required this.open,
    required this.onToggle,
  });

  final String name;
  final String? group;
  final String? type;
  final String? note;
  final String? count;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.labelMedium!.copyWith(
      fontWeight: FontWeight.w400,
      color: style.colors.inkMuted,
    );
    final group = this.group;
    final onToggle = this.onToggle;
    final header = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: onToggle == null ? 40 : ForgeTheme.tapMin,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          spacing: 10,
          children: [
            if (group != null) SetBubble.letter(group),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: text.titleMedium),
                  if (type case final type?) Text(type, style: muted),
                  if (note case final note?) Text(note, style: muted),
                ],
              ),
            ),
            if (count case final count?)
              Text(
                count,
                style: style.data.copyWith(color: style.colors.inkMuted),
              ),
            if (onToggle != null)
              ForgeIcon(
                open ? ForgeIcons.expandLess : ForgeIcons.expandMore,
                size: 18,
                color: style.colors.inkMuted,
              ),
          ],
        ),
      ),
    );
    if (onToggle == null) return header;
    return Semantics(
      button: true,
      expanded: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: header,
      ),
    );
  }
}

/// A group's A1 / A2 letter in a surface-sunken circle.
class _Row extends StatelessWidget {
  const _Row({required this.row});

  final SetTableRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: style.colors.line)),
      ),
      child: Row(
        spacing: 10,
        children: [
          SetBubble(
            label: row.label,
            semanticLabel: row.label,
            onTap: null,
            done: true,
            small: true,
          ),
          Expanded(
            child: Text(
              row.values,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.data.copyWith(fontSize: 15, color: style.colors.ink),
            ),
          ),
          if (row.record)
            ForgeTag(
              l10n.setTableRecord,
              kind: ForgeTagKind.record,
              icon: ForgeIcons.emojiEvents,
            ),
          ForgeTag(row.effort ?? '—'),
        ],
      ),
    );
  }
}

class _SetNote extends StatelessWidget {
  const _SetNote(this.note);

  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(left: SetTable._indent, bottom: 10),
      child: Row(
        spacing: 6,
        children: [
          ForgeIcon(ForgeIcons.description, size: 14, color: colors.inkMuted),
          Expanded(
            child: Text(
              note,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropRow extends StatelessWidget {
  const _DropRow({required this.values, required this.number});

  final String values;
  final int number;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final muted = style.colors.inkMuted;
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.only(left: SetTable._indent),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: Text(
                values,
                style: style.data.copyWith(fontSize: 13, color: muted),
              ),
            ),
            ForgeTag(
              AppLocalizations.of(context).workoutDrop(number),
              kind: ForgeTagKind.plain,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditHeader extends StatelessWidget {
  const _EditHeader({
    required this.name,
    required this.group,
    required this.note,
    required this.menu,
  });

  final String name;
  final String? group;
  final String? note;
  final List<ForgeMenuItem> menu;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final group = this.group;
    final note = this.note;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ForgeTheme.tapMin),
      child: Row(
        spacing: Gap.sm,
        children: [
          if (group != null) SetBubble.letter(group),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.titleMedium),
                if (note != null)
                  Text(
                    note,
                    style: text.labelMedium!.copyWith(
                      fontWeight: FontWeight.w400,
                      color: style.colors.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          Builder(
            builder: (context) => ForgeIconButton(
              icon: ForgeIcons.moreHoriz,
              label: AppLocalizations.of(context).setTableOptions,
              onPressed: () => showForgeMenu(context: context, items: menu),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({required this.row, required this.divided});

  final SetTableEditRow row;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final effort = ForgeTag(row.effort ?? '—');
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: divided
          ? BoxDecoration(
              border: Border(top: BorderSide(color: colors.line)),
            )
          : null,
      child: Row(
        spacing: Gap.sm,
        children: [
          Builder(
            builder: (bubble) => Semantics(
              button: true,
              checked: row.done,
              label: row.semanticLabel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: row.onToggle,
                onLongPress: () => row.onOptions(bubble),
                child: SizedBox.square(
                  dimension: ForgeTheme.tapMin,
                  child: Center(
                    child: ExcludeSemantics(
                      child: SetBubble(
                        label: row.label,
                        semanticLabel: row.label,
                        onTap: null,
                        done: row.done,
                        small: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ..._inputs(row.inputs, colors),
          const Spacer(),
          if (row.onEffort case final onEffort?)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEffort,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ForgeTheme.tapMin,
                  ),
                  child: Center(child: effort),
                ),
              ),
            )
          else
            effort,
        ],
      ),
    );
  }
}

/// [inputs] as small boxes joined by "×".
List<Widget> _inputs(List<SetTableInput> inputs, ForgePalette colors) => [
  for (final (i, input) in inputs.indexed) ...[
    if (i > 0) Text('×', style: TextStyle(color: colors.inkMuted)),
    ForgeNumberField.compact(
      label: input.label,
      width: input.wide ? 70 : 50,
      controller: input.controller,
      onChanged: input.onChanged,
    ),
  ],
];

/// A drop of a set being edited: its boxes under the set, indented, and
/// "Drop 1" at the end.
class _EditDropRow extends StatelessWidget {
  const _EditDropRow({required this.inputs, required this.number});

  final List<SetTableInput> inputs;
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(left: SetTable._indent, bottom: 6),
      child: Row(
        spacing: Gap.sm,
        children: [
          ..._inputs(inputs, colors),
          const Spacer(),
          ForgeTag(
            AppLocalizations.of(context).workoutDrop(number),
            kind: ForgeTagKind.plain,
          ),
        ],
      ),
    );
  }
}

class _AddSet extends StatelessWidget {
  const _AddSet({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: ForgeTheme.tapMin),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.line)),
          ),
          child: Row(
            spacing: 6,
            children: [
              ForgeIcon(ForgeIcons.add, size: 18, color: colors.ink),
              Text(
                AppLocalizations.of(context).workoutAddSet,
                style: Theme.of(context).textTheme.labelLarge!
                    .copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A set's 28px bubble: its label in mono on accent when [done], else on
/// a line-strong ring.
// SetBubble's small done form, drawn here until that component lands.
