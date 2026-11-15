import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';

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

/// One set of a [SetTable.edit]: its bubble's [label], its values in
/// small boxes joined by "×" ([inputs]), and its [effort].
class SetTableEditRow {
  const SetTableEditRow({
    required this.label,
    required this.inputs,
    this.effort,
  });

  final String label;
  final List<SetTableInput> inputs;
  final String? effort;
}

/// The sets of an exercise in history, on a card: the exercise's [name],
/// its [group] letter (A1) in a sunken circle before it, its logging
/// [type] and [note] under it, then a row per set (see [SetTableRow]).
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
  }) : editRows = null,
       menu = null,
       onAddSet = null;

  const SetTable.edit({
    super.key,
    required this.name,
    required List<SetTableEditRow> rows,
    required List<ForgeMenuItem> this.menu,
    required VoidCallback this.onAddSet,
  }) : rows = null,
       editRows = rows,
       group = null,
       type = null,
       note = null;

  final String name;
  final List<SetTableRow>? rows;
  final List<SetTableEditRow>? editRows;
  final String? group;
  final String? type;
  final String? note;
  final List<ForgeMenuItem>? menu;
  final VoidCallback? onAddSet;

  /// Where a set's drops and note start: past its bubble and the gap.
  static const _indent = _bubbleSize + 10;
  static const _bubbleSize = 28.0;

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
            _EditHeader(name: name, menu: menu!),
            for (final (i, row) in editRows.indexed)
              _EditRow(row: row, divided: i > 0),
            _AddSet(onPressed: onAddSet!),
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
          _Header(name: name, group: group, type: type, note: note),
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
  });

  final String name;
  final String? group;
  final String? type;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.labelMedium!.copyWith(
      fontWeight: FontWeight.w400,
      color: style.colors.inkMuted,
    );
    final group = this.group;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          spacing: 10,
          children: [
            if (group != null)
              Container(
                width: SetTable._bubbleSize,
                height: SetTable._bubbleSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: style.colors.surfaceSunken,
                ),
                child: Text(
                  group,
                  style: style.data.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: style.colors.ink,
                  ),
                ),
              ),
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
          ],
        ),
      ),
    );
  }
}

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
          _Bubble(row.label),
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
  const _EditHeader({required this.name, required this.menu});

  final String name;
  final List<ForgeMenuItem> menu;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: ForgeTheme.tapMin),
    child: Row(
      children: [
        Expanded(
          child: Text(name, style: Theme.of(context).textTheme.titleMedium),
        ),
        Builder(
          builder: (context) => Semantics(
            button: true,
            label: AppLocalizations.of(context).setTableOptions,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showForgeMenu(context: context, items: menu),
              child: SizedBox.square(
                dimension: ForgeTheme.tapMin,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ForgeIcon(
                    ForgeIcons.moreHoriz,
                    size: 20,
                    color: ForgeStyle.of(context).colors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EditRow extends StatelessWidget {
  const _EditRow({required this.row, required this.divided});

  final SetTableEditRow row;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final times = Text('×', style: TextStyle(color: colors.inkMuted));
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
          _Bubble(row.label),
          for (final (i, input) in row.inputs.indexed) ...[
            if (i > 0) times,
            ForgeNumberField.compact(
              label: input.label,
              width: input.wide ? 70 : 50,
              controller: input.controller,
              onChanged: input.onChanged,
            ),
          ],
          const Spacer(),
          ForgeTag(row.effort ?? '—'),
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

/// A done set's 28px bubble: its label in mono on accent.
// SetBubble's small done form, drawn here until that component lands.
class _Bubble extends StatelessWidget {
  const _Bubble(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return Container(
      width: SetTable._bubbleSize,
      height: SetTable._bubbleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: style.colors.accent,
      ),
      child: Text(
        label,
        style: style.data.copyWith(fontSize: 11, color: style.colors.onAccent),
      ),
    );
  }
}
