import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import '../domain/rules_changes.dart';
import 'generator_rules_cubit.dart';
import 'rule_fields.dart';

/// The width of the template list on the AG2 board.
const _listWidth = 260.0;

/// The longest split or day name, and split info, as the rules allow.
const _maxName = 40;
const _maxInfo = 200;

/// The splits with their templates on the left, the open template on the
/// right: its fields, a tab per day and the day's slots (AG2 A).
class TemplatesTab extends StatelessWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final open = context.select(
      (GeneratorRulesCubit cubit) => cubit.state.openTemplate,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.md,
      children: [
        const SizedBox(width: _listWidth, child: _TemplateList()),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: open == null
                  ? const EmptyView(message: 'Pick a template, or add one.')
                  : _TemplateEditor(open),
            ),
          ),
        ),
      ],
    );
  }
}

String _splitName(Map<Object?, Object?> split) => switch (split) {
  {'l10n': {'en': {'name': final String name}}} when name.isNotEmpty => name,
  _ => '${split['id']}',
};

/// The splits in the order the app offers them, each with its templates,
/// then New template and New split.
class _TemplateList extends StatelessWidget {
  const _TemplateList();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final draft = state.draft!;
    final splits = draft.splits;
    final templates = draft.templates;
    final splitIds = {for (final split in splits) split['id']};
    final theme = Theme.of(context);
    Widget templateRow(int t) {
      final template = templates[t];
      final hasProblem = state.problems.any(
        (problem) => problem.concerns(['templates', t]),
      );
      return ListTile(
        dense: true,
        selected: t == state.openTemplate,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        title: Text('${template['id']} · ${template['days']} days'),
        trailing: hasProblem
            ? Icon(Icons.error_outline, color: theme.colorScheme.error)
            : null,
        onTap: () => cubit.selectTemplate(t),
      );
    }

    final orphans = [
      for (final (t, template) in templates.indexed)
        if (!splitIds.contains(template['split'])) t,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (s, split) in splits.indexed) ...[
              _SplitHeading(
                index: s,
                split: split,
                last: s == splits.length - 1,
                used: templates.any((t) => t['split'] == split['id']),
              ),
              for (final (t, template) in templates.indexed)
                if (template['split'] == split['id']) templateRow(t),
            ],
            if (orphans.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(Gap.sm),
                child: Text('No split', style: theme.textTheme.labelLarge),
              ),
              for (final t in orphans) templateRow(t),
            ],
            FieldProblems(state.problemsAt(const ['splits'], exact: true)),
            FieldProblems(state.problemsAt(const ['templates'], exact: true)),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              onPressed: splits.isEmpty ? null : cubit.addTemplate,
              icon: const Icon(Icons.add),
              label: const Text('New template'),
            ),
            TextButton.icon(
              onPressed: () => _editSplit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('New split'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A split's name over its templates, with its menu: edit, move, and
/// remove while no template uses it.
class _SplitHeading extends StatelessWidget {
  const _SplitHeading({
    required this.index,
    required this.split,
    required this.last,
    required this.used,
  });

  final int index;
  final JsonMap split;
  final bool last;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final path = ['splits', index];
    final problems = state.problemsAt(path);
    return Padding(
      padding: const EdgeInsets.only(left: Gap.sm, top: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _splitName(split),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: 'Split ${split['id']}',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: () => _editSplit(context, index),
                    child: const Text('Edit split'),
                  ),
                  PopupMenuItem(
                    enabled: index > 0,
                    value: () => cubit.moveItem(['splits'], index, index - 1),
                    child: const Text('Move up'),
                  ),
                  PopupMenuItem(
                    enabled: !last,
                    value: () => cubit.moveItem(['splits'], index, index + 1),
                    child: const Text('Move down'),
                  ),
                  PopupMenuItem(
                    enabled: !used,
                    value: () => cubit.removeItem(['splits'], index),
                    child: Text(
                      used
                          ? 'Remove split (a template uses it)'
                          : 'Remove split',
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (state.wasAt([...path, 'l10n']) case final was?) WasText(was),
          FieldProblems(problems),
        ],
      ),
    );
  }
}

/// Edits split [index] (null: a new one) in a dialog; its id only while it
/// is new.
Future<void> _editSplit(BuildContext context, int? index) async {
  final cubit = context.read<GeneratorRulesCubit>();
  final state = cubit.state;
  final draft = state.draft!;
  final split = index == null ? null : draft.splits[index];
  final isNew = split == null || state.rules?.splitIndex(split['id']) == null;
  final edited = await showDialog<JsonMap>(
    context: context,
    builder: (_) => _SplitDialog(split: split, idEditable: isNew),
  );
  if (edited == null) return;
  if (index == null) {
    cubit.addItem(['splits'], edited);
  } else {
    cubit.setValue(['splits', index], edited);
  }
}

class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.split, required this.idEditable});

  final JsonMap? split;
  final bool idEditable;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  late final JsonMap _split = widget.split ?? {'id': '', 'l10n': {}};
  late final Map<Object?, Object?> _l10n =
      _split['l10n'] as Map<Object?, Object?>? ?? {};
  late final Map<Object?, Object?> _en =
      _l10n['en'] as Map<Object?, Object?>? ?? {};
  late final _id = TextEditingController(text: '${_split['id'] ?? ''}');
  late final _name = TextEditingController(text: '${_en['name'] ?? ''}');
  late final _info = TextEditingController(text: '${_en['info'] ?? ''}');

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _info.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.split == null ? 'New split' : 'Edit split'),
      content: SizedBox(
        width: maxFormWidth / 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            TextField(
              controller: _id,
              enabled: widget.idEditable,
              decoration: const InputDecoration(
                labelText: 'Id',
                helperText:
                    'Lower case letters, digits and _; fixed once '
                    'published.',
              ),
            ),
            TextField(
              controller: _name,
              maxLength: _maxName,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Saved programs are named "<name>, n days".',
              ),
            ),
            TextField(
              controller: _info,
              maxLength: _maxInfo,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Info',
                helperText: 'One line under the split in the app.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, <String, Object?>{
            ..._split,
            'id': _id.text.trim(),
            'l10n': {
              ..._l10n,
              'en': {..._en, 'name': _name.text, 'info': _info.text},
            },
          }),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// The open template: its fields, a tab per day, the open day.
class _TemplateEditor extends StatelessWidget {
  const _TemplateEditor(this.index);

  final int index;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final draft = state.draft!;
    final path = ['templates', index];
    final id = draft.at([...path, 'id']);
    final isNew = state.rules?.templateIndex(id) == null;
    final days = (draft.at([...path, 'dayList']) as List?) ?? const [];
    final day = state.openDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.md,
      children: [
        Wrap(
          spacing: Gap.md,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: RuleText([...path, 'id'], label: 'Id', enabled: isNew),
            ),
            SizedBox(width: 240, child: _SplitPicker(index)),
            SizedBox(width: 140, child: _DaysPicker(index)),
            RuleNumber([...path, 'priority'], label: 'Priority', width: 100),
          ],
        ),
        RuleCodes([...path, 'levels'], label: 'Levels', values: Level.values),
        RuleCodes(
          [...path, 'goals'],
          label: 'Goals',
          values: Goal.values,
          every: 'Every goal',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              if (await _confirm(
                context,
                title: 'Delete template $id?',
                body:
                    'It leaves the draft; Discard brings it back until you '
                    'publish.',
                action: 'Delete template',
              )) {
                cubit.removeTemplate(index);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete template'),
          ),
        ),
        if (days.isNotEmpty) ...[
          DefaultTabController(
            // A new controller when the template, its days or the open day
            // change elsewhere.
            key: ValueKey((index, days.length, day)),
            length: days.length,
            initialIndex: day,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: cubit.selectDay,
              tabs: [
                for (var d = 0; d < days.length; d++)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Gap.xs,
                      children: [
                        Text(switch (days[d]) {
                          {'l10n': {'en': {'name': final String name}}}
                              when name.isNotEmpty =>
                            name,
                          _ => 'Day ${d + 1}',
                        }),
                        if (state.problems.any(
                          (problem) =>
                              problem.concerns([...path, 'dayList', d]),
                        ))
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.error,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _DayEditor(index, day),
        ],
      ],
    );
  }
}

class _SplitPicker extends StatelessWidget {
  const _SplitPicker(this.template);

  final int template;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final path = ['templates', template, 'split'];
    final value = state.valueAt(path);
    final splits = state.draft!.splits;
    final known = splits.any((split) => split['id'] == value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<Object?>(
          key: ValueKey((template, value)),
          initialValue: known ? value : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Split', isDense: true),
          items: [
            for (final split in splits)
              DropdownMenuItem(
                value: split['id'],
                child: Text(_splitName(split)),
              ),
          ],
          onChanged: (id) => cubit.setValue(path, id),
        ),
        WasText(state.wasAt(path)),
        FieldProblems(state.problemsAt(path)),
      ],
    );
  }
}

/// Days a week, 2-6: adds days at the end or removes the last ones,
/// asking first when one has slots.
class _DaysPicker extends StatelessWidget {
  const _DaysPicker(this.template);

  final int template;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final path = ['templates', template, 'days'];
    final value = state.valueAt(path);
    final dayList =
        (state.valueAt(['templates', template, 'dayList']) as List?) ??
        const [];
    Future<void> change(int? days) async {
      if (days == null) return;
      final removed = [
        for (var d = days; d < dayList.length; d++)
          if (dayList[d] case {'slots': final List<Object?> slots}
              when slots.isNotEmpty)
            d,
      ];
      if (removed.isNotEmpty &&
          !await _confirm(
            context,
            title: 'Remove ${removed.length} day(s) with slots?',
            body:
                'Days ${[for (final d in removed) d + 1].join(', ')} and '
                'their slots leave the template.',
            action: 'Remove',
          )) {
        return;
      }
      cubit.setDays(template, days);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey((template, value)),
          initialValue: value is int && value >= 2 && value <= 6 ? value : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Days a week',
            isDense: true,
          ),
          items: [
            for (var n = 2; n <= 6; n++)
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: change,
        ),
        WasText(state.wasAt(path)),
        FieldProblems([
          ...state.problemsAt(path),
          ...state.problemsAt(['templates', template, 'dayList'], exact: true),
        ]),
      ],
    );
  }
}

/// A day's slots as table rows, Add slot, its name and its extras.
class _DayEditor extends StatelessWidget {
  const _DayEditor(this.template, this.day);

  final int template;
  final int day;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final dayPath = ['templates', template, 'dayList', day];
    final slotsPath = [...dayPath, 'slots'];
    final slots = (state.valueAt(slotsPath) as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        RulesTable(
          header: const [
            '#',
            'Role',
            'Picks an exercise with',
            'Priority',
            'Key',
            '',
          ],
          rows: [
            for (var s = 0; s < slots.length; s++)
              if ([...slotsPath, s] case final slot)
                [
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: Text('${s + 1}'),
                  ),
                  _RoleCell(slot),
                  _PickCell(slot),
                  _PriorityCell(slot),
                  SizedBox(
                    width: 100,
                    child: RuleText([...slot, 'key'], optional: true),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: s == 0
                            ? null
                            : () => cubit.moveItem(slotsPath, s, s - 1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        onPressed: s == slots.length - 1
                            ? null
                            : () => cubit.moveItem(slotsPath, s, s + 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: 'Remove slot',
                        onPressed: () => cubit.removeItem(slotsPath, s),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
          ],
        ),
        FieldProblems([
          ...state.problemsAt(dayPath, exact: true),
          ...state.problemsAt(slotsPath, exact: true),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () =>
                cubit.addItem(slotsPath, newSlot(first: slots.isEmpty)),
            icon: const Icon(Icons.add),
            label: const Text('Add slot'),
          ),
        ),
        SizedBox(
          width: 320,
          child: RuleText(
            [...dayPath, 'l10n', 'en', 'name'],
            label: 'Day name',
            maxLength: _maxName,
          ),
        ),
        RuleCodes(
          [...dayPath, 'extras'],
          label: 'Extra focus work may be added for',
          values: Muscle.values,
        ),
      ],
    );
  }
}

class _RoleCell extends StatelessWidget {
  const _RoleCell(this.slot);

  final RulesPath slot;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final path = [...slot, 'role'];
    final role = SlotRole.values.byCode(state.valueAt(path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<SlotRole>(
          value: role,
          hint: const Text('Role'),
          items: [
            for (final value in SlotRole.values)
              DropdownMenuItem(value: value, child: Text(codeLabel(value))),
          ],
          onChanged: (value) => cubit.setValue(path, value?.code),
        ),
        WasText(state.wasAt(path)),
        FieldProblems(state.problemsAt(path)),
      ],
    );
  }
}

class _PriorityCell extends StatelessWidget {
  const _PriorityCell(this.slot);

  final RulesPath slot;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final path = [...slot, 'priority'];
    final priority = state.valueAt(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            for (final n in [1, 2, 3])
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {if (priority is num) priority.toInt()},
          onSelectionChanged: (picked) {
            if (picked.isNotEmpty) cubit.setValue(path, picked.single);
          },
        ),
        WasText(state.wasAt(path)),
        FieldProblems(state.problemsAt(path)),
      ],
    );
  }
}

/// What a slot picks, as chips, edited in a dialog.
class _PickCell extends StatelessWidget {
  const _PickCell(this.slot);

  final RulesPath slot;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final path = [...slot, 'pick'];
    final pick = state.valueAt(path);
    final labels = pickLabels(pick);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    if (labels.isEmpty) const Hint('Nothing yet'),
                    for (final label in labels)
                      Chip(
                        label: Text(label),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit picks',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final edited = await showDialog<JsonMap>(
                    context: context,
                    builder: (_) => PickDialog(
                      pick: pick is Map ? pick.cast<String, Object?>() : {},
                    ),
                  );
                  if (edited != null) cubit.setValue(path, edited);
                },
              ),
            ],
          ),
          WasText(state.wasAt(path)),
          FieldProblems(state.problemsAt(path)),
        ],
      ),
    );
  }
}

/// Edits a slot's pick: patterns, muscles and mechanic, and pops it.
class PickDialog extends StatefulWidget {
  const PickDialog({super.key, required this.pick});

  final JsonMap pick;

  @override
  State<PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<PickDialog> {
  late final _patterns = {
    ...?(widget.pick['patterns'] as List?)?.map((code) => '$code'),
  };
  late final _muscles = {
    ...?(widget.pick['muscles'] as List?)?.map((code) => '$code'),
  };
  late String? _mechanic = widget.pick['mechanic'] as String?;

  Widget _chips<T extends Coded>(List<T> values, Set<String> selected) => Wrap(
    spacing: Gap.xs,
    runSpacing: Gap.xs,
    children: [
      for (final value in values)
        FilterChip(
          label: Text(codeLabel(value)),
          selected: selected.contains(value.code),
          onSelected: (on) => setState(
            () => on ? selected.add(value.code) : selected.remove(value.code),
          ),
        ),
    ],
  );

  /// [codes] in the order [key] had them, the new ones after in
  /// vocabulary order, so an unchanged pick stays unchanged.
  List<String> _ordered<T extends Coded>(
    String key,
    List<T> values,
    Set<String> codes,
  ) {
    final before = [
      for (final code in widget.pick[key] as List? ?? const []) '$code',
    ];
    return [
      for (final code in before)
        if (codes.contains(code)) code,
      for (final value in values)
        if (codes.contains(value.code) && !before.contains(value.code))
          value.code,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge;
    return AlertDialog(
      title: const Text('Picks an exercise with'),
      content: SizedBox(
        width: maxFormWidth * 0.66,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.sm,
            children: [
              const Hint(
                'An exercise fits when its pattern is one of the patterns, '
                'one of its main muscles is one of the muscles and its '
                'mechanic is the mechanic, each only when given. Patterns or '
                'muscles are needed.',
              ),
              Text('Movement patterns', style: label),
              _chips(MovementPattern.values, _patterns),
              Text('Main muscles', style: label),
              _chips(Muscle.values, _muscles),
              Text('Mechanic', style: label),
              Wrap(
                spacing: Gap.xs,
                children: [
                  for (final mechanic in [null, ...Mechanic.values])
                    ChoiceChip(
                      label: Text(
                        mechanic == null ? 'Any' : codeLabel(mechanic),
                      ),
                      selected: _mechanic == mechanic?.code,
                      onSelected: (_) =>
                          setState(() => _mechanic = mechanic?.code),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final pick = {...widget.pick}
              ..remove('patterns')
              ..remove('muscles')
              ..remove('mechanic');
            Navigator.pop(context, <String, Object?>{
              ...pick,
              if (_patterns.isNotEmpty)
                'patterns': _ordered(
                  'patterns',
                  MovementPattern.values,
                  _patterns,
                ),
              if (_muscles.isNotEmpty)
                'muscles': _ordered('muscles', Muscle.values, _muscles),
              'mechanic': ?_mechanic,
            });
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
