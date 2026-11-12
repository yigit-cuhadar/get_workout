import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/grouping.dart';
import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_program.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../../../features/programs/domain/program.dart';
import '../../admin_router.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../../shell/editor_status.dart';
import 'program_editor_cubit.dart';

/// Creates a ready-made program ([id] null) or edits one: its card, its
/// text, and its days with their exercises, with the catalogue rules'
/// problems shown next to the fields they concern.
class ProgramEditorPage extends StatelessWidget {
  const ProgramEditorPage({super.key, required this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ProgramEditorCubit>(param1: id),
    child: const _EditorView(),
  );
}

class _EditorView extends StatelessWidget {
  const _EditorView();

  void _show(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProgramEditorCubit, ProgramEditorState>(
      listenWhen: (previous, state) =>
          previous.status != state.status ||
          (previous.problems.isEmpty && state.problems.isNotEmpty),
      listener: (context, state) {
        switch (state.status) {
          case EditorStatus.saved:
            _show(context, 'Saved as ${codeLabel(state.draft.status)}.');
            // A new program gets its own address once it exists.
            if (GoRouterState.of(context).matchedLocation ==
                AdminRoutes.newProgram) {
              context.go(AdminRoutes.program(state.draft.id));
            }
          case EditorStatus.saveFailed:
            _show(
              context,
              state.accessRefreshed
                  ? 'The save was refused, but this account still has admin '
                        'access and its token is now refreshed. Save again.'
                  : failureMessage(state.failure!),
            );
          case EditorStatus.editing when state.problems.isNotEmpty:
            _show(context, 'Not saved: ${state.problems.length} problem(s).');
          default:
        }
      },
      builder: (context, state) {
        final cubit = context.read<ProgramEditorCubit>();
        if (state.status == EditorStatus.loadFailed) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(
              message: failureMessage(state.failure!),
              onRetry: cubit.reload,
            ),
          );
        }
        if (state.status == EditorStatus.loading) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        final stored = state.isNew ? null : state.loaded?.draft;
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () => context.go(AdminRoutes.programs),
            ),
            title: Text(
              stored == null
                  ? 'New program'
                  : '${stored.textOf(CatalogueProgram.fallbackLanguage).name} (${stored.id})',
            ),
            actions: [
              Center(
                child: Text(
                  [
                    'Stored: ${stored == null ? 'not yet' : codeLabel(stored.status)}',
                    if (state.isDirty) 'unsaved changes',
                  ].join(' · '),
                ),
              ),
              const SizedBox(width: Gap.md),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.status == EditorStatus.changedSinceLoaded)
                MaterialBanner(
                  content: const Text(
                    'This program changed since you opened it, so your save '
                    'was refused. Reload it (your changes here are lost) and '
                    'make them again.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: cubit.reload,
                      child: const Text('Reload'),
                    ),
                  ],
                ),
              Expanded(child: _Form(state: state)),
              const Divider(height: 1),
              StatusActions(
                noun: 'program',
                liveEffect: "It appears in every user's catalogue.",
                hiddenEffect:
                    "It leaves every user's catalogue; copies users "
                    'already made stay theirs.',
                stored: stored?.status,
                saving: state.status == EditorStatus.saving,
                canSave: state.canSave,
                onSave: cubit.save,
                onSaveAs: cubit.saveAs,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.state});

  final ProgramEditorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProgramEditorCubit>();
    final draft = state.draft;
    List<String> problems(String field) => state.problemsFor(field);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxFormWidth),
        // The list stays when the fields are rebuilt, so the scroll does.
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            // A replaced draft, or days and items added, moved or removed,
            // rebuild every field.
            KeyedSubtree(
              key: ValueKey(state.formVersion),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.problems.isNotEmpty)
                    ProblemSummary(
                      title: '${state.problems.length} problem(s) block saving',
                      messages: [for (final p in state.problems) p.message],
                    ),
                  FormSection(
                    title: 'Card',
                    children: [
                      FormRow([
                        TextInput(
                          label:
                              'Id (pr_ + snake_case; cannot change once saved)',
                          value: draft.id,
                          enabled: state.isNew,
                          problems: problems('id'),
                          onChanged: (id) =>
                              cubit.change((d) => d.copyWith(id: id)),
                        ),
                        NumberInput(
                          label: 'Order in the catalogue (1 first, unique)',
                          value: draft.order,
                          problems: problems('order'),
                          onChanged: (order) =>
                              cubit.change((d) => d.copyWith(order: order)),
                        ),
                      ]),
                      SwitchListTile(
                        title: const Text('Premium'),
                        subtitle: const Text(
                          'Only users with premium can read its days.',
                        ),
                        value: draft.premium,
                        onChanged: (premium) =>
                            cubit.change((d) => d.copyWith(premium: premium)),
                      ),
                      FieldProblems(problems('premium')),
                      FormRow([
                        CodePicker<Level>(
                          label: 'Level',
                          values: Level.values,
                          value: draft.level,
                          problems: problems('level'),
                          onChanged: (v) =>
                              cubit.change((d) => d.copyWith(level: v)),
                        ),
                        CodePicker<Goal>(
                          label: 'Goal',
                          values: Goal.values,
                          value: draft.goal,
                          problems: problems('goal'),
                          onChanged: (v) =>
                              cubit.change((d) => d.copyWith(goal: v)),
                        ),
                        CodePicker<EquipmentProfile>(
                          label: 'Equipment profile (every exercise fits it)',
                          values: EquipmentProfile.values,
                          value: draft.equipmentProfile,
                          problems: problems('equipmentProfile'),
                          onChanged: (v) => cubit.change(
                            (d) => d.copyWith(equipmentProfile: v),
                          ),
                        ),
                      ]),
                      NumberInput(
                        label:
                            'Length in weeks (optional, '
                            '${ProgramLimits.minLengthWeeks}-'
                            '${ProgramLimits.maxLengthWeeks})',
                        value: draft.lengthWeeks,
                        problems: problems('lengthWeeks'),
                        onChanged: (weeks) =>
                            cubit.change((d) => d.copyWith(lengthWeeks: weeks)),
                      ),
                    ],
                  ),
                  for (final language in languages)
                    FormSection(
                      title: 'Text (${language.toUpperCase()})',
                      children: [
                        TextInput(
                          label:
                              'Name (1-${ProgramLimits.maxNameLength} characters, '
                              'unique)',
                          value: draft.textOf(language).name,
                          problems: problems('l10n.$language.name'),
                          onChanged: (name) => cubit.change(
                            (d) => d.withText(
                              language,
                              CatalogueText(
                                name: name,
                                summary: d.textOf(language).summary,
                              ),
                            ),
                          ),
                        ),
                        TextInput(
                          label:
                              'Summary (${summarySentences.min}-'
                              '${summarySentences.max} full sentences)',
                          value: draft.textOf(language).summary,
                          multiline: true,
                          problems: problems('l10n.$language.summary'),
                          onChanged: (summary) => cubit.change(
                            (d) => d.withText(
                              language,
                              CatalogueText(
                                name: d.textOf(language).name,
                                summary: summary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  _Computed(state: state),
                  for (final (index, _) in draft.days.indexed)
                    _DaySection(state: state, day: index),
                  FieldProblems(problems('days')),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: draft.days.length < ProgramLimits.maxDays
                          ? cubit.addDay
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Add day (max ${ProgramLimits.maxDays})',
                      ),
                    ),
                  ),
                  // Problems about fields the form has no input for, e.g. across
                  // the catalogue or an unknown field written in the console.
                  FieldProblems([
                    for (final problem in state.problems)
                      if (!_formFields.contains(problem.field) &&
                          !problem.field.startsWith('days['))
                        problem.message,
                  ]),
                ],
              ),
            ),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }
}

/// The fields the form shows the problems of, but the days, which show
/// their own.
final _formFields = {
  'id',
  'order',
  'premium',
  'level',
  'goal',
  'equipmentProfile',
  'lengthWeeks',
  'days',
  for (final language in languages)
    for (final key in programTextKeys) 'l10n.$language.$key',
};

/// What is stored on the card but computed from the days, and the numbers
/// the catalogue rules hold the program to.
class _Computed extends StatelessWidget {
  const _Computed({required this.state});

  final ProgramEditorState state;

  @override
  Widget build(BuildContext context) {
    final content = state.content;
    final summary = state.summary;
    final minutes = content['minutes'];
    final equipment = content['equipment']! as List<String>;
    final band = weeklySetBands[state.draft.level];
    final warnings = state.warnings;
    final warningStyle = TextStyle(
      color: Theme.of(context).colorScheme.tertiary,
    );
    return FormSection(
      title: 'Computed from the days (stored on the card)',
      children: [
        Text('Days per week: ${content['daysPerWeek']}'),
        Text('Equipment: ${equipment.isEmpty ? '-' : equipment.join(', ')}'),
        Text(
          minutes is Map
              ? 'Minutes: ${minutes['min']}-${minutes['max']} '
                    '(per day: ${summary.minutesPerDay.join(', ')})'
              : 'Minutes: -',
        ),
        Text(
          [
            'Weekly sets of the major muscles'
                '${band == null ? '' : ' (${band.min}-${band.max} for this level)'}:',
            for (final muscle in majorMuscles)
              '${codeLabel(muscle)} '
                  '${formatSets(summary.weeklySets[muscle] ?? 0)}',
          ].join(' '),
        ),
        if (warnings.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final warning in warnings)
                Text('Warning: $warning', style: warningStyle),
              Text(
                'Warnings never block a save; a focus or equipment-limited '
                'program says why in its summary.',
                style: warningStyle,
              ),
            ],
          ),
      ],
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.state, required this.day});

  final ProgramEditorState state;
  final int day;

  Future<void> _addExercise(BuildContext context) async {
    final live = [
      for (final record in state.exercises.values)
        if (record.draft.status == ExerciseStatus.live) record.draft,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => ExercisePickerDialog(
        choices: [for (final exercise in live) exercise.id],
        names: {for (final exercise in live) exercise.id: exercise.name},
      ),
    );
    if (picked != null && context.mounted) {
      context.read<ProgramEditorCubit>().addExercise(day, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProgramEditorCubit>();
    final days = state.draft.days;
    final items = days[day].items;
    final field = 'days[$day]';
    return FormSection(
      title: 'Day ${day + 1}',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextInput(
                label: 'Name (1-${ProgramLimits.maxDayNameLength} characters)',
                value: days[day].name,
                problems: state.problemsFor('$field.name'),
                onChanged: (name) => cubit.renameDay(day, name),
              ),
            ),
            IconButton(
              tooltip: 'Move day up',
              onPressed: day == 0 ? null : () => cubit.moveDay(day, day - 1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Move day down',
              onPressed: day == days.length - 1
                  ? null
                  : () => cubit.moveDay(day, day + 1),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              tooltip: 'Remove day',
              onPressed: () => cubit.removeDay(day),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        for (final (index, _) in items.indexed)
          _ItemRow(state: state, day: day, item: index),
        FieldProblems([
          ...state.problemsFor(field),
          ...state.problemsFor('$field.items'),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: items.length < ProgramLimits.maxItemsPerDay
                ? () => _addExercise(context)
                : null,
            icon: const Icon(Icons.add),
            label: const Text(
              'Add exercise (max ${ProgramLimits.maxItemsPerDay})',
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.state, required this.day, required this.item});

  final ProgramEditorState state;
  final int day;
  final int item;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProgramEditorCubit>();
    final items = state.draft.days[day].items;
    final value = items[item];
    final exercise = state.exercises[value.exerciseId]?.draft;
    final timed = exercise?.loggingType?.isDurationBased ?? false;
    void edit(ProgramItem Function(ProgramItem item) change) =>
        cubit.changeItem(day, item, change);
    final group = value.group;
    final groupSize = items.where((i) => group != null && i.group == group);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      '${item + 1}. ${exercise?.name ?? 'Unknown exercise'} '
                          '(${value.exerciseId})',
                      if (exercise != null &&
                          exercise.status != ExerciseStatus.live)
                        codeLabel(exercise.status),
                      if (exercise?.loggingType case final type?)
                        codeLabel(type),
                      if (group != null)
                        '${groupSize.length > 2 ? 'Circuit' : 'Superset'} '
                            '$group',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: item == 0
                      ? null
                      : () => cubit.moveItem(day, item, item - 1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: item == items.length - 1
                      ? null
                      : () => cubit.moveItem(day, item, item + 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Link with the next (superset or circuit)',
                  onPressed: canLinkWithNext(items, item)
                      ? () => cubit.linkWithNext(day, item)
                      : null,
                  icon: const Icon(Icons.link),
                ),
                IconButton(
                  tooltip: 'Ungroup',
                  onPressed: group == null
                      ? null
                      : () => cubit.ungroup(day, item),
                  icon: const Icon(Icons.link_off),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => cubit.removeItem(day, item),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            FormRow([
              NumberInput(
                key: const ValueKey('sets'),
                label:
                    'Sets (${ProgramLimits.minSets}-${ProgramLimits.maxSets})',
                value: value.sets < 0 ? null : value.sets,
                onChanged: (v) => edit((i) => i.copyWith(sets: v ?? -1)),
              ),
              // A target the exercise does not take shows while it is set,
              // so it can be cleared.
              if (!timed || value.repMin != null || value.repMax != null) ...[
                NumberInput(
                  key: const ValueKey('repMin'),
                  label: 'Reps from',
                  value: value.repMin,
                  onChanged: (v) => edit((i) => i.copyWith(repMin: () => v)),
                ),
                NumberInput(
                  key: const ValueKey('repMax'),
                  label: 'Reps to',
                  value: value.repMax,
                  onChanged: (v) => edit((i) => i.copyWith(repMax: () => v)),
                ),
              ],
              if (timed || value.durationS != null)
                NumberInput(
                  key: const ValueKey('durationS'),
                  label:
                      'Duration (s, ${ProgramLimits.minDurationS}-'
                      '${ProgramLimits.maxDurationS})',
                  value: value.durationS,
                  onChanged: (v) => edit((i) => i.copyWith(durationS: () => v)),
                ),
              NumberInput(
                key: const ValueKey('restS'),
                label: 'Rest (s, 0-${ProgramLimits.maxRestS})',
                value: value.restS < 0 ? null : value.restS,
                onChanged: (v) => edit((i) => i.copyWith(restS: v ?? -1)),
              ),
            ]),
            FieldProblems(state.problemsWithin('days[$day].items[$item]')),
          ],
        ),
      ),
    );
  }
}
