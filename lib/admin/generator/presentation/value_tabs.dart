import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import 'generator_rules_cubit.dart';
import 'generator_sizes.dart';
import 'rule_fields.dart';

/// The weekly sets aimed for per muscle and level, and the cap per level.
class VolumeTab extends StatelessWidget {
  const VolumeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.titleSmall;
    return FormSection(
      title: 'Weekly sets',
      children: [
        const Hint(
          'Sets a week aimed for, counted 1 per main and 0.5 per secondary '
          'muscle. 0: the muscle is only trained through other exercises. '
          'Added sets and slots never take a muscle above the cap.',
        ),
        RulesTable(
          header: [
            'Muscle',
            for (final level in Level.values) codeLabel(level),
          ],
          rows: [
            for (final muscle in Muscle.values)
              [
                Text(codeLabel(muscle)),
                for (final level in Level.values)
                  RuleNumber([
                    'volume',
                    'targets',
                    level.code,
                    muscle.code,
                  ], blank: 0),
              ],
          ],
          footer: [
            Text('Cap', style: label),
            for (final level in Level.values)
              RuleNumber(['volume', 'cap', level.code]),
          ],
        ),
      ],
    );
  }
}

/// What makes an exercise score higher for a slot.
class SelectionTab extends StatelessWidget {
  const SelectionTab({super.key});

  /// The five single scores, with what each does.
  static const _scores = {
    'aboveLevel': (
      'Above level',
      'Added for an exercise one level above the user.',
    ),
    'repeat': ('Repeat', 'Added for an exercise already used this week.'),
    'family': ('Family', 'Added when its family is already used this week.'),
    'popularity': ('Popularity', 'The most the popularity order adds.'),
    'variety': ('Variety', 'The most the seed adds.'),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.md,
      children: [
        FormSection(
          title: 'Tier',
          children: [
            const Hint(
              'Added for the exercise’s generator tier. A never exercise is '
              'not picked at all; a fallback one only fills a priority 1 '
              'slot.',
            ),
            Wrap(
              spacing: Gap.lg,
              children: [
                for (final tier in GeneratorTier.values)
                  if (tier != GeneratorTier.never)
                    RuleNumber(
                      ['selection', 'tier', tier.code],
                      label: codeLabel(tier),
                      decimal: true,
                      width: GeneratorSizes.labelled,
                    ),
              ],
            ),
          ],
        ),
        FormSection(
          title: 'Equipment',
          children: [
            const Hint(
              'The score of doing an exercise with this equipment, by the '
              'equipment style the user prefers. An exercise scores as the '
              'first item of its best set the user has.',
            ),
            RulesTable(
              header: [
                'Equipment',
                for (final style in EquipmentStyle.values) codeLabel(style),
              ],
              rows: [
                for (final equipment in Equipment.values)
                  [
                    Text(codeLabel(equipment)),
                    for (final style in EquipmentStyle.values)
                      RuleNumber([
                        'selection',
                        'equipment',
                        style.code,
                        equipment.code,
                      ], decimal: true),
                  ],
              ],
            ),
          ],
        ),
        const _GoalExtras(),
        FormSection(
          title: 'Other scores',
          children: [
            for (final MapEntry(key: key, value: (label, hint))
                in _scores.entries)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.md,
                children: [
                  RuleNumber(
                    ['selection', key],
                    label: label,
                    decimal: true,
                    width: GeneratorSizes.labelled,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Hint(hint),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// `selection.goalEquipment`: a score added for a goal and an equipment,
/// as rows of goal, equipment and score.
class _GoalExtras extends StatelessWidget {
  const _GoalExtras();

  static const _path = ['selection', 'goalEquipment'];

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final byGoal = state.valueAt(_path);
    final rows = [
      if (byGoal is Map)
        for (final goal in Goal.values)
          if (byGoal[goal.code] case final Map<Object?, Object?> scores)
            for (final equipment in Equipment.values)
              if (scores.containsKey(equipment.code)) (goal, equipment),
    ];
    bool taken(Goal goal, Equipment equipment) =>
        rows.contains((goal, equipment));

    /// Moves the score of [from] to [to] (removes it without), dropping a
    /// goal left empty.
    void move((Goal, Equipment) from, [(Goal, Equipment)? to]) {
      final score = state.valueAt([..._path, from.$1.code, from.$2.code]);
      cubit.setValue(_path, {
        for (final goal in Goal.values)
          if ({
                for (final (g, e) in rows)
                  if ((g, e) != from && g == goal)
                    e.code: state.valueAt([..._path, g.code, e.code]),
                if (to case (final toGoal, final toEquipment)
                    when toGoal == goal)
                  toEquipment.code: score,
              }
              case final scores when scores.isNotEmpty)
            goal.code: scores,
      });
    }

    void add() {
      for (final goal in Goal.values) {
        for (final equipment in Equipment.values) {
          if (!taken(goal, equipment)) {
            cubit.setValue([..._path, goal.code, equipment.code], 0);
            return;
          }
        }
      }
    }

    return FormSection(
      title: 'Goal extras',
      children: [
        const Hint(
          'Added to an equipment’s score for one goal, such as barbells '
          'for getting stronger.',
        ),
        FieldProblems(state.problemsAt(_path, exact: true)),
        for (final (goal, equipment) in rows)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.md,
            children: [
              SizedBox(
                width: GeneratorSizes.wide,
                child: DropdownButtonFormField<Goal>(
                  initialValue: goal,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Goal'),
                  items: [
                    for (final g in Goal.values)
                      if (g == goal || !taken(g, equipment))
                        DropdownMenuItem(value: g, child: Text(codeLabel(g))),
                  ],
                  onChanged: (g) {
                    if (g != null && g != goal) {
                      move((goal, equipment), (g, equipment));
                    }
                  },
                ),
              ),
              SizedBox(
                width: GeneratorSizes.wide,
                child: DropdownButtonFormField<Equipment>(
                  initialValue: equipment,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Equipment'),
                  items: [
                    for (final e in Equipment.values)
                      if (e == equipment || !taken(goal, e))
                        DropdownMenuItem(value: e, child: Text(codeLabel(e))),
                  ],
                  onChanged: (e) {
                    if (e != null && e != equipment) {
                      move((goal, equipment), (goal, e));
                    }
                  },
                ),
              ),
              RuleNumber(
                [..._path, goal.code, equipment.code],
                label: 'Score',
                decimal: true,
                width: GeneratorSizes.short,
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => move((goal, equipment)),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: add,
            icon: const Icon(Icons.add),
            label: const Text('Add extra'),
          ),
        ),
      ],
    );
  }
}

/// The focus and leave-out areas, the session time and the program length.
class AreasTab extends StatelessWidget {
  const AreasTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.md,
      children: [
        FormSection(
          title: 'Focus',
          children: [
            const Hint(
              'The muscles of each area a user may focus on: their weekly '
              'target and cap rise by the extra sets, and their slots come '
              'first.',
            ),
            for (final area in FocusArea.values)
              RuleCodes(
                ['focus', 'areas', area.code],
                label: codeLabel(area),
                values: Muscle.values,
              ),
            const Wrap(
              spacing: Gap.lg,
              children: [
                RuleNumber(
                  ['focus', 'extraSets'],
                  label: 'Extra sets',
                  width: GeneratorSizes.labelled,
                ),
                RuleNumber(
                  ['focus', 'max'],
                  label: 'Areas a user may pick',
                  width: GeneratorSizes.wide,
                ),
              ],
            ),
          ],
        ),
        FormSection(
          title: 'Leave out',
          children: [
            const Hint(
              'The muscles left out with each area a user does not want to '
              'train: no exercise with one of them as a main muscle, and no '
              'target for them.',
            ),
            for (final area in FocusArea.values)
              RuleCodes(
                ['skip', 'areas', area.code],
                label: codeLabel(area),
                values: Muscle.values,
              ),
            const RuleNumber(
              ['skip', 'max'],
              label: 'Areas a user may leave out',
              width: GeneratorSizes.wide,
            ),
          ],
        ),
        const FormSection(
          title: 'Time',
          children: [
            RuleNumber(
              ['time', 'setupS'],
              label: 'Setup per exercise (s)',
              width: GeneratorSizes.wide,
            ),
            _SessionMinutes(),
          ],
        ),
        FormSection(
          title: 'Length in weeks',
          children: [
            const Hint('The length a generated program is saved with.'),
            Wrap(
              spacing: Gap.lg,
              children: [
                for (final level in Level.values)
                  RuleNumber(
                    ['lengthWeeks', level.code],
                    label: codeLabel(level),
                    width: GeneratorSizes.labelled,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// The session lengths offered, shortest first.
class _SessionMinutes extends StatelessWidget {
  const _SessionMinutes();

  static const _path = ['time', 'sessionMinutes'];

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final minutes = state.valueAt(_path);
    final count = minutes is List ? minutes.length : 0;
    final last = count == 0 ? null : (minutes as List).last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.xs,
      children: [
        Text(
          'Session lengths offered (min), shortest first',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RuleNumber([..._path, i]),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => cubit.removeItem(_path, i),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () =>
                  cubit.addItem(_path, last is num ? last + 15 : 30),
              icon: const Icon(Icons.add),
              label: const Text('Add length'),
            ),
          ],
        ),
        WasText(state.wasAt(_path)),
        FieldProblems(state.problemsAt(_path, exact: true)),
      ],
    );
  }
}
