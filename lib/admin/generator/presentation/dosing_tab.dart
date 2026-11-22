import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import 'generator_rules_cubit.dart';
import 'rule_fields.dart';

/// The dose of each slot role for one goal (AG1 A), and the grouping rules
/// under it.
class DosingTab extends StatelessWidget {
  const DosingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final goal = context.select(
      (GeneratorRulesCubit cubit) => cubit.state.dosingGoal,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.md,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.sm,
              children: [
                Wrap(
                  spacing: Gap.xs,
                  children: [
                    for (final value in Goal.values)
                      ChoiceChip(
                        label: Text(codeLabel(value)),
                        selected: value.code == goal,
                        onSelected: (_) => cubit.selectDosingGoal(value.code),
                      ),
                  ],
                ),
                _DoseTable(goal),
              ],
            ),
          ),
        ),
        const _Grouping(),
      ],
    );
  }
}

class _DoseTable extends StatelessWidget {
  const _DoseTable(this.goal);

  final String goal;

  @override
  Widget build(BuildContext context) {
    return RulesTable(
      header: [
        'Role',
        for (final level in Level.values) 'Sets, ${level.code}',
        'Reps',
        'Bodyweight reps',
        'Hold (s) B / I / A',
        'Rest (s)',
      ],
      rows: [
        for (final role in SlotRole.values)
          if (['dosing', goal, role.code] case final dose)
            [
              Text(
                codeLabel(role),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final level in Level.values)
                RuleRange([...dose, 'sets', level.code]),
              RuleRange([...dose, 'reps']),
              RuleRange([...dose, 'bodyweightReps']),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.xs,
                children: [
                  for (final level in Level.values)
                    RuleNumber([
                      ...dose,
                      'holdS',
                      level.code,
                    ], width: numberWidth * 0.75),
                ],
              ),
              RuleNumber([...dose, 'restS']),
            ],
      ],
    );
  }
}

/// The grouping rules, in order: the first that fits applies.
class _Grouping extends StatelessWidget {
  const _Grouping();

  static const _list = ['grouping'];

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final count = (state.valueAt(_list) as List?)?.length ?? 0;
    return FormSection(
      title: 'Grouping',
      children: [
        const Hint(
          'The first rule that fits the answers joins neighbouring slots of '
          'its roles: two make supersets, more make circuits, rested after '
          'each round. With none, every exercise is straight sets.',
        ),
        FieldProblems(state.problemsAt(_list, exact: true)),
        for (var i = 0; i < count; i++) _GroupingRule(i, last: i == count - 1),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => cubit.addItem(_list, {
              'roles': ['accessory'],
              'size': 2,
              'restS': 60,
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add rule'),
          ),
        ),
      ],
    );
  }
}

class _GroupingRule extends StatelessWidget {
  const _GroupingRule(this.index, {required this.last});

  final int index;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final path = ['grouping', index];
    const list = ['grouping'];
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rule ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: index == 0
                      ? null
                      : () => cubit.moveItem(list, index, index - 1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: last
                      ? null
                      : () => cubit.moveItem(list, index, index + 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => cubit.removeItem(list, index),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            RuleCodes(
              [...path, 'goals'],
              label: 'Goals',
              values: Goal.values,
              every: 'Every goal',
            ),
            RuleCodes(
              [...path, 'roles'],
              label: 'Roles',
              values: SlotRole.values,
            ),
            Wrap(
              spacing: Gap.lg,
              runSpacing: Gap.sm,
              children: [
                RuleNumber(
                  [...path, 'sessionMax'],
                  label: 'Sessions up to (min)',
                  width: 160,
                ),
                _SizePicker([...path, 'size']),
                RuleNumber(
                  [...path, 'restS'],
                  label: 'Rest after a round (s)',
                  width: 160,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// How many slots a group joins: 2 to 4.
class _SizePicker extends StatelessWidget {
  const _SizePicker(this.path);

  final RulesPath path;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final size = state.valueAt(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Size', style: Theme.of(context).textTheme.labelLarge),
        SegmentedButton<int>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            for (final n in [2, 3, 4])
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {if (size is num) size.toInt()},
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
