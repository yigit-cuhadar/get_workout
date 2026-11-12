import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../admin_router.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../../shell/editor_status.dart';
import '../domain/exercise_draft.dart';
import 'exercise_editor_cubit.dart';

/// Creates an exercise ([id] null) or edits one, field by field, with the
/// content rules' problems shown next to the fields they concern.
class ExerciseEditorPage extends StatelessWidget {
  const ExerciseEditorPage({super.key, required this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ExerciseEditorCubit>(param1: id),
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
    return BlocConsumer<ExerciseEditorCubit, ExerciseEditorState>(
      listenWhen: (previous, state) =>
          previous.status != state.status ||
          (previous.problems.isEmpty && state.problems.isNotEmpty),
      listener: (context, state) {
        switch (state.status) {
          case EditorStatus.saved:
            _show(context, 'Saved as ${codeLabel(state.draft.status)}.');
            // A new exercise gets its own address once it exists.
            if (GoRouterState.of(context).matchedLocation ==
                AdminRoutes.newExercise) {
              context.go(AdminRoutes.exercise(state.draft.id));
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
        final cubit = context.read<ExerciseEditorCubit>();
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
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () => context.go(AdminRoutes.exercises),
            ),
            title: Text(
              state.isNew
                  ? 'New exercise'
                  : '${state.loaded?.draft.name} (${state.draft.id})',
            ),
            actions: [
              Center(
                child: Text(
                  [
                    'Stored: ${state.isNew ? 'not yet' : codeLabel(state.loaded!.draft.status)}',
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
                    'This exercise changed since you opened it, so your save '
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
              Expanded(
                // Replaced drafts (a reload) rebuild every field.
                child: KeyedSubtree(
                  key: ValueKey(state.formVersion),
                  child: _Form(state: state),
                ),
              ),
              const Divider(height: 1),
              _Actions(state: state),
            ],
          ),
        );
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state});

  final ExerciseEditorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExerciseEditorCubit>();
    return StatusActions(
      noun: 'exercise',
      liveEffect: 'It becomes visible to every user at their next sync.',
      hiddenEffect: 'Users stop seeing it at their next sync.',
      stored: state.isNew ? null : state.loaded?.draft.status,
      saving: state.status == EditorStatus.saving,
      canSave: state.canSave,
      onSave: cubit.save,
      onSaveAs: cubit.saveAs,
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.state});

  final ExerciseEditorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExerciseEditorCubit>();
    final draft = state.draft;
    void edit(ExerciseDraft Function(ExerciseDraft d) change) =>
        cubit.change(change);
    List<String> problems(String field) => state.problemsFor(field);
    final otherIds = [
      for (final record in state.library)
        if (record.id != draft.id) record.id,
    ]..sort();
    final names = {
      for (final record in state.library) record.id: record.draft.name,
    };

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxFormWidth),
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            if (state.problems.isNotEmpty)
              ProblemSummary(
                title: '${state.problems.length} problem(s) block saving',
                messages: [for (final p in state.problems) p.message],
              ),
            FormSection(
              title: 'Identity',
              children: [
                TextInput(
                  label: 'Id (ex_ + snake_case; cannot change once saved)',
                  value: draft.id,
                  enabled: state.isNew,
                  problems: problems('id'),
                  onChanged: (id) => edit((d) => d.copyWith(id: id)),
                ),
                TextInput(
                  label: 'Name (English)',
                  value: draft.name,
                  problems: problems('l10n.en.name'),
                  onChanged: (name) => edit((d) => d.copyWith(name: name)),
                ),
                FormRow([
                  TextInput(
                    label: 'Family (snake_case)',
                    value: draft.family,
                    problems: problems('family'),
                    onChanged: (family) =>
                        edit((d) => d.copyWith(family: family)),
                  ),
                  NumberInput(
                    label: 'Family rank (1 = easiest)',
                    value: draft.familyRank,
                    problems: problems('familyRank'),
                    onChanged: (rank) =>
                        edit((d) => d.copyWith(familyRank: rank)),
                  ),
                  NumberInput(
                    label: 'Popularity (1 sorts first)',
                    value: draft.popularity,
                    problems: problems('popularity'),
                    onChanged: (value) =>
                        edit((d) => d.copyWith(popularity: value)),
                  ),
                ]),
              ],
            ),
            FormSection(
              title: 'Classification',
              children: [
                FormRow([
                  CodePicker<LoggingType>(
                    label: 'Logging type',
                    values: LoggingType.values,
                    value: draft.loggingType,
                    problems: problems('loggingType'),
                    onChanged: (v) => edit((d) => d.copyWith(loggingType: v)),
                  ),
                  CodePicker<Mechanic>(
                    label: 'Mechanic',
                    values: Mechanic.values,
                    value: draft.mechanic,
                    problems: problems('mechanic'),
                    onChanged: (v) => edit((d) => d.copyWith(mechanic: v)),
                  ),
                  CodePicker<Laterality>(
                    label: 'Laterality',
                    values: Laterality.values,
                    value: draft.laterality,
                    problems: problems('laterality'),
                    onChanged: (v) => edit((d) => d.copyWith(laterality: v)),
                  ),
                ]),
                FormRow([
                  CodePicker<Level>(
                    label: 'Level',
                    values: Level.values,
                    value: draft.level,
                    problems: problems('level'),
                    onChanged: (v) => edit((d) => d.copyWith(level: v)),
                  ),
                  CodePicker<Force>(
                    label: 'Force',
                    values: Force.values,
                    value: draft.force,
                    problems: problems('force'),
                    onChanged: (v) => edit((d) => d.copyWith(force: v)),
                  ),
                  CodePicker<MovementPattern>(
                    label: 'Movement pattern',
                    values: MovementPattern.values,
                    value: draft.movementPattern,
                    problems: problems('movementPattern'),
                    onChanged: (v) =>
                        edit((d) => d.copyWith(movementPattern: v)),
                  ),
                ]),
                FormRow([
                  CodePicker<Position>(
                    label: 'Position',
                    values: Position.values,
                    value: draft.position,
                    problems: problems('position'),
                    onChanged: (v) => edit((d) => d.copyWith(position: v)),
                  ),
                  CodePicker<Grip>(
                    label: 'Grip (optional)',
                    values: Grip.values,
                    value: draft.grip,
                    optional: true,
                    problems: problems('grip'),
                    onChanged: (v) => edit((d) => d.copyWith(grip: v)),
                  ),
                  CodePicker<GripWidth>(
                    label: 'Grip width (optional)',
                    values: GripWidth.values,
                    value: draft.gripWidth,
                    optional: true,
                    problems: problems('gripWidth'),
                    onChanged: (v) => edit((d) => d.copyWith(gripWidth: v)),
                  ),
                ]),
                FormRow([
                  NumberInput(
                    label: 'Default rest (s, $minRestS-$maxRestS)',
                    value: draft.defaultRestS,
                    problems: problems('defaultRestS'),
                    onChanged: (v) => edit((d) => d.copyWith(defaultRestS: v)),
                  ),
                  if (draft.takesIncrement)
                    _DecimalInput(
                      label: 'Weight increment (kg)',
                      value: draft.incrementKg,
                      problems: problems('incrementKg'),
                      onChanged: (v) => edit((d) => d.copyWith(incrementKg: v)),
                    )
                  else
                    const Text('No weight increment for this logging type.'),
                ]),
              ],
            ),
            FormSection(
              title: 'Equipment',
              children: [
                _CodeChips<Equipment>(
                  label: 'Equipment (all needed together)',
                  values: Equipment.values,
                  selected: draft.equipment,
                  problems: problems('equipment'),
                  onChanged: (v) => edit((d) => d.copyWith(equipment: v)),
                ),
                for (final (index, set) in draft.equipmentAlternatives.indexed)
                  _CodeChips<Equipment>(
                    label: 'Alternative set ${index + 1}',
                    values: Equipment.values,
                    selected: set,
                    onChanged: (v) => edit(
                      (d) => d.copyWith(
                        equipmentAlternatives: [...d.equipmentAlternatives]
                          ..[index] = v,
                      ),
                    ),
                    onRemove: () => edit(
                      (d) => d.copyWith(
                        equipmentAlternatives: [...d.equipmentAlternatives]
                          ..removeAt(index),
                      ),
                    ),
                  ),
                FieldProblems(problems('equipmentAlternatives')),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        draft.equipmentAlternatives.length <
                            maxEquipmentAlternatives
                        ? () => edit(
                            (d) => d.copyWith(
                              equipmentAlternatives: [
                                ...d.equipmentAlternatives,
                                const [],
                              ],
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Add alternative set (max $maxEquipmentAlternatives)',
                    ),
                  ),
                ),
              ],
            ),
            FormSection(
              title: 'Muscles',
              children: [
                _CodeChips<Muscle>(
                  label: 'Main muscles (1-$maxMainMuscles)',
                  values: Muscle.values,
                  selected: draft.mainMuscles,
                  problems: problems('mainMuscles'),
                  onChanged: (v) => edit((d) => d.copyWith(mainMuscles: v)),
                ),
                _CodeChips<Muscle>(
                  label: 'Secondary muscles (0-$maxSecondaryMuscles)',
                  values: Muscle.values,
                  selected: draft.secondaryMuscles,
                  problems: problems('secondaryMuscles'),
                  onChanged: (v) =>
                      edit((d) => d.copyWith(secondaryMuscles: v)),
                ),
              ],
            ),
            FormSection(
              title: 'Alternatives (overrides of the computed list)',
              children: [
                _IdList(
                  label: 'Pinned (shown first)',
                  ids: draft.pinnedAlternatives,
                  choices: otherIds,
                  names: names,
                  problems: problems('pinnedAlternatives'),
                  onChanged: (v) =>
                      edit((d) => d.copyWith(pinnedAlternatives: v)),
                ),
                _IdList(
                  label: 'Excluded (never shown)',
                  ids: draft.excludedAlternatives,
                  choices: otherIds,
                  names: names,
                  problems: problems('excludedAlternatives'),
                  onChanged: (v) =>
                      edit((d) => d.copyWith(excludedAlternatives: v)),
                ),
              ],
            ),
            FormSection(
              title: 'Text (English)',
              children: [
                _StringList(
                  label: 'Aliases (0-$maxAliases)',
                  values: draft.aliases,
                  problems: problems('l10n.en.aliases'),
                  onChanged: (v) => edit((d) => d.copyWith(aliases: v)),
                ),
                _StringList(
                  label: 'Setup (${setupLines.min}-${setupLines.max})',
                  values: draft.setup,
                  problems: problems('l10n.en.setup'),
                  onChanged: (v) => edit((d) => d.copyWith(setup: v)),
                ),
                _StringList(
                  label:
                      'Execution (${executionLines.min}-${executionLines.max})',
                  values: draft.execution,
                  problems: problems('l10n.en.execution'),
                  onChanged: (v) => edit((d) => d.copyWith(execution: v)),
                ),
                _StringList(
                  label: 'Mistakes (${mistakeLines.min}-${mistakeLines.max})',
                  values: draft.mistakes,
                  problems: problems('l10n.en.mistakes'),
                  onChanged: (v) => edit((d) => d.copyWith(mistakes: v)),
                ),
                TextInput(
                  label: 'Safety (optional)',
                  value: draft.safety ?? '',
                  problems: problems('l10n.en.safety'),
                  onChanged: (v) =>
                      edit((d) => d.copyWith(safety: v.isEmpty ? null : v)),
                ),
                _StringList(
                  label: 'Cues (${cueLines.min}-${cueLines.max})',
                  values: draft.cues,
                  problems: problems('l10n.en.cues'),
                  onChanged: (v) => edit((d) => d.copyWith(cues: v)),
                ),
              ],
            ),
            // Problems about fields the form has no input for, e.g. an unknown
            // field written in the console.
            FieldProblems([
              for (final problem in state.problems)
                if (!_formFields.contains(problem.field)) problem.message,
            ]),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }
}

/// The fields the form has inputs for: every known field but `l10n` itself,
/// whose English text fields have their own inputs.
final _formFields = {
  ...allowedKeys.difference({'l10n'}),
  for (final key in allowedTextKeys) 'l10n.en.$key',
};

class _DecimalInput extends StatelessWidget {
  const _DecimalInput({
    required this.label,
    required this.value,
    required this.onChanged,
    this.problems = const [],
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: value?.toString() ?? '',
          decoration: InputDecoration(labelText: label),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (text) => onChanged(double.tryParse(text)),
        ),
        FieldProblems(problems),
      ],
    );
  }
}

/// A multi-select of codes, kept in vocabulary order.
class _CodeChips<T extends Coded> extends StatelessWidget {
  const _CodeChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.onRemove,
    this.problems = const [],
  });

  final String label;
  final List<T> values;
  final List<T> selected;
  final ValueChanged<List<T>> onChanged;
  final VoidCallback? onRemove;
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            if (onRemove != null)
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove set'),
              ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: [
            for (final value in values)
              FilterChip(
                label: Text(codeLabel(value)),
                selected: selected.contains(value),
                onSelected: (on) => onChanged([
                  for (final v in values)
                    if (v == value ? on : selected.contains(v)) v,
                ]),
              ),
          ],
        ),
        FieldProblems(problems),
      ],
    );
  }
}

/// Exercise ids picked from the loaded library.
class _IdList extends StatelessWidget {
  const _IdList({
    required this.label,
    required this.ids,
    required this.choices,
    required this.names,
    required this.onChanged,
    this.problems = const [],
  });

  final String label;
  final List<String> ids;
  final List<String> choices;
  final Map<String, String> names;
  final ValueChanged<List<String>> onChanged;
  final List<String> problems;

  Future<void> _add(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => ExercisePickerDialog(
        choices: [
          for (final id in choices)
            if (!ids.contains(id)) id,
        ],
        names: names,
      ),
    );
    if (picked != null) onChanged([...ids, picked]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: [
            for (final id in ids)
              InputChip(
                label: Text('${names[id] ?? 'Unknown'} ($id)'),
                onDeleted: () => onChanged([...ids]..remove(id)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add),
              label: const Text('Add'),
              onPressed: () => _add(context),
            ),
          ],
        ),
        FieldProblems(problems),
      ],
    );
  }
}

/// An ordered list of lines: edit, add, remove and move up or down.
class _StringList extends StatefulWidget {
  const _StringList({
    required this.label,
    required this.values,
    required this.onChanged,
    this.problems = const [],
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<String> problems;

  @override
  State<_StringList> createState() => _StringListState();
}

class _StringListState extends State<_StringList> {
  // One controller per line, moved with its line, so the cursor stays put.
  late final List<TextEditingController> _lines = [
    for (final value in widget.values) TextEditingController(text: value),
  ];

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _publish() => widget.onChanged([for (final line in _lines) line.text]);

  void _update(VoidCallback change) {
    setState(change);
    _publish();
  }

  void _move(int from, int to) => _update(() {
    final line = _lines.removeAt(from);
    _lines.insert(to, line);
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        for (final (index, line) in _lines.indexed)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line,
                    maxLines: null,
                    decoration: InputDecoration(labelText: '${index + 1}'),
                    onChanged: (_) => _publish(),
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: index == 0 ? null : () => _move(index, index - 1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: index == _lines.length - 1
                      ? null
                      : () => _move(index, index + 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _update(() {
                    final removed = _lines.removeAt(index);
                    // Its field still holds it until the next frame.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => removed.dispose(),
                    );
                  }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _update(() => _lines.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Add line'),
          ),
        ),
        FieldProblems(widget.problems),
      ],
    );
  }
}
