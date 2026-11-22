import 'package:material_ui/material_ui.dart';
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
import '../../shell/page_header.dart';
import '../../shell/problem_card.dart';
import '../../shell/save_bar.dart';
import '../../shell/status_tag.dart';
import '../domain/exercise_draft.dart';
import 'exercise_editor_cubit.dart';

/// The editor's sections, one tab each.
enum ExerciseEditorTab {
  identity('Identity'),
  classification('Classification'),
  equipment('Equipment'),
  muscles('Muscles'),
  alternatives('Alternatives'),
  text('Text (English)'),
  generator('Generator');

  const ExerciseEditorTab(this.label);

  final String label;
}

/// Every field the form has an input for: its tab and its short name in the
/// problem card.
const exerciseEditorFields = <String, (ExerciseEditorTab, String)>{
  'id': (ExerciseEditorTab.identity, 'Id'),
  'l10n.en.name': (ExerciseEditorTab.identity, 'Name'),
  'family': (ExerciseEditorTab.identity, 'Family'),
  'familyRank': (ExerciseEditorTab.identity, 'Family rank'),
  'popularity': (ExerciseEditorTab.identity, 'Popularity'),
  'loggingType': (ExerciseEditorTab.classification, 'Logging type'),
  'mechanic': (ExerciseEditorTab.classification, 'Mechanic'),
  'laterality': (ExerciseEditorTab.classification, 'Laterality'),
  'level': (ExerciseEditorTab.classification, 'Level'),
  'force': (ExerciseEditorTab.classification, 'Force'),
  'movementPattern': (ExerciseEditorTab.classification, 'Movement pattern'),
  'position': (ExerciseEditorTab.classification, 'Position'),
  'grip': (ExerciseEditorTab.classification, 'Grip'),
  'gripWidth': (ExerciseEditorTab.classification, 'Grip width'),
  'defaultRestS': (ExerciseEditorTab.classification, 'Default rest'),
  'incrementKg': (ExerciseEditorTab.classification, 'Weight increment'),
  'equipment': (ExerciseEditorTab.equipment, 'Equipment'),
  'equipmentAlternatives': (ExerciseEditorTab.equipment, 'Alternative sets'),
  'mainMuscles': (ExerciseEditorTab.muscles, 'Main muscles'),
  'secondaryMuscles': (ExerciseEditorTab.muscles, 'Secondary muscles'),
  'pinnedAlternatives': (ExerciseEditorTab.alternatives, 'Pinned'),
  'excludedAlternatives': (ExerciseEditorTab.alternatives, 'Excluded'),
  'l10n.en.aliases': (ExerciseEditorTab.text, 'Aliases'),
  'l10n.en.setup': (ExerciseEditorTab.text, 'Setup'),
  'l10n.en.execution': (ExerciseEditorTab.text, 'Execution'),
  'l10n.en.mistakes': (ExerciseEditorTab.text, 'Mistakes'),
  'l10n.en.safety': (ExerciseEditorTab.text, 'Safety'),
  'l10n.en.cues': (ExerciseEditorTab.text, 'Cues'),
  'generatorTier': (ExerciseEditorTab.generator, 'Generator tier'),
  'stressAreas': (ExerciseEditorTab.generator, 'Stress areas'),
};

/// What a generator tier means, under its name.
String _tierMeaning(GeneratorTier tier) => switch (tier) {
  GeneratorTier.staple => 'A first choice for its slot.',
  GeneratorTier.standard => 'A good alternative.',
  GeneratorTier.fallback => 'Only when nothing better fits the equipment.',
  GeneratorTier.never => 'The generator does not use it.',
};

/// Creates an exercise ([id] null) or edits one, a section per tab, with
/// the content rules' problems summed up at the top, marked on their tabs
/// and shown under the fields they concern.
class ExerciseEditorPage extends StatelessWidget {
  const ExerciseEditorPage({super.key, required this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ExerciseEditorCubit>(param1: id),
    child: const _EditorView(),
  );
}

class _EditorView extends StatefulWidget {
  const _EditorView();

  @override
  State<_EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<_EditorView>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: ExerciseEditorTab.values.length,
    vsync: this,
  )..addListener(() => setState(() {}));
  final _anchors = FieldAnchors();

  @override
  void dispose() {
    _tabs.dispose();
    _anchors.dispose();
    super.dispose();
  }

  ExerciseEditorTab get _tab => ExerciseEditorTab.values[_tabs.index];

  /// Opens the tab of [field], then brings the field into view.
  void _open(String field) {
    final (tab, _) = exerciseEditorFields[field]!;
    _tabs.index = tab.index;
    WidgetsBinding.instance.addPostFrameCallback((_) => _anchors.open(field));
  }

  void _show(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _toList() => context.go(AdminRoutes.exercises);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExerciseEditorCubit, ExerciseEditorState>(
      listenWhen: (previous, state) =>
          previous.status != state.status ||
          (previous.problems.isEmpty && state.problems.isNotEmpty),
      listener: (context, state) {
        switch (state.status) {
          case EditorStatus.saved:
            _show('Saved as ${codeLabel(state.draft.status)}.');
            // A new exercise gets its own address once it exists.
            if (GoRouterState.of(context).matchedLocation ==
                AdminRoutes.newExercise) {
              context.go(AdminRoutes.exercise(state.draft.id));
            }
          case EditorStatus.saveFailed:
            _show(
              state.accessRefreshed
                  ? 'The save was refused, but this account still has admin '
                        'access and its token is now refreshed. Save again.'
                  : failureMessage(state.failure!),
            );
          case EditorStatus.editing when state.problems.isNotEmpty:
            _show('Not saved: ${state.problems.length} problem(s).');
          default:
        }
      },
      builder: (context, state) {
        final cubit = context.read<ExerciseEditorCubit>();
        if (state.status == EditorStatus.loadFailed) {
          return Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: _toList)),
            body: ErrorView(
              title: "Couldn't load the exercise",
              message: failureMessage(state.failure!),
              onRetry: cubit.reload,
              retryLabel: 'Retry',
            ),
          );
        }
        if (state.status == EditorStatus.loading) {
          return Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: _toList)),
            body: const LoadingView(),
          );
        }
        final stored = state.isNew ? null : state.loaded;
        final tabsWithProblems = {
          for (final problem in state.problems)
            if (exerciseEditorFields[problem.field] case (final tab, _)) tab,
        };
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxFormWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(Gap.lg),
                      children: [
                        PageHeader(
                          back: ('Exercises', _toList),
                          title: stored?.draft.name ?? 'New exercise',
                          subtitle: stored == null
                              ? 'Not saved yet'
                              : '${stored.id} · last saved '
                                    '${dateTimeLabel(stored.updatedAt)}',
                          trailing: [
                            if (stored != null) StatusTag(stored.draft.status),
                            if (state.isDirty)
                              const ForgeTag(
                                'Unsaved changes',
                                kind: ForgeTagKind.category,
                              ),
                          ],
                        ),
                        const SizedBox(height: Gap.md),
                        if (state.status == EditorStatus.changedSinceLoaded)
                          MaterialBanner(
                            content: const Text(
                              'This exercise changed since you opened it, so '
                              'your save was refused. Reload it (your changes '
                              'here are lost) and make them again.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: cubit.reload,
                                child: const Text('Reload'),
                              ),
                            ],
                          ),
                        if (state.problems.isNotEmpty) ...[
                          ProblemCard(
                            lines: [
                              for (final problem in state.problems)
                                (
                                  label:
                                      exerciseEditorFields[problem.field]?.$2 ??
                                      problem.field,
                                  message: problem.message,
                                  onOpen:
                                      exerciseEditorFields.containsKey(
                                        problem.field,
                                      )
                                      ? () => _open(problem.field)
                                      : null,
                                ),
                            ],
                          ),
                          const SizedBox(height: Gap.md),
                        ],
                        TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            for (final tab in ExerciseEditorTab.values)
                              Tab(
                                child: _TabLabel(
                                  tab.label,
                                  hasProblem: tabsWithProblems.contains(tab),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Gap.md),
                        // A replaced draft (a reload) or another tab
                        // rebuilds every field.
                        KeyedSubtree(
                          key: ValueKey((state.formVersion, _tab)),
                          child: _Section(
                            tab: _tab,
                            state: state,
                            anchors: _anchors,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.lg,
                      0,
                      Gap.lg,
                      Gap.lg,
                    ),
                    child: SaveBar(
                      noun: 'exercise',
                      liveEffect:
                          'It becomes visible to every user at their next '
                          'sync.',
                      hiddenEffect: 'Users stop seeing it at their next sync.',
                      stored: stored?.draft.status,
                      dirty: state.isDirty,
                      saving: state.status == EditorStatus.saving,
                      canSave: state.canSave,
                      onSave: cubit.save,
                      onSaveAs: cubit.saveAs,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A tab's name, with a mark when a field on it has a problem.
class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.hasProblem});

  final String label;
  final bool hasProblem;

  /// The diameter of the problem mark.
  static const _mark = 8.0;

  @override
  Widget build(BuildContext context) {
    if (!hasProblem) return Text(label);
    return Semantics(
      label: '$label, has problems',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Gap.xs,
        children: [
          Text(label),
          Container(
            width: _mark,
            height: _mark,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ForgeStyle.of(context).colors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// The fields of one tab, each wrapped in its anchor.
class _Section extends StatelessWidget {
  const _Section({
    required this.tab,
    required this.state,
    required this.anchors,
  });

  final ExerciseEditorTab tab;
  final ExerciseEditorState state;
  final FieldAnchors anchors;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExerciseEditorCubit>();
    final draft = state.draft;
    void edit(ExerciseDraft Function(ExerciseDraft d) change) =>
        cubit.change(change);
    List<String> problems(String field) => state.problemsFor(field);
    final a = anchors.anchor;

    return switch (tab) {
      ExerciseEditorTab.identity => FormSection(
        title: tab.label,
        children: [
          a(
            'id',
            TextInput(
              label: 'Id (ex_ + snake_case; cannot change once saved)',
              value: draft.id,
              enabled: state.isNew,
              problems: problems('id'),
              onChanged: (id) => edit((d) => d.copyWith(id: id)),
            ),
          ),
          a(
            'l10n.en.name',
            TextInput(
              label: 'Name (English)',
              value: draft.name,
              problems: problems('l10n.en.name'),
              onChanged: (name) => edit((d) => d.copyWith(name: name)),
            ),
          ),
          FormRow([
            a(
              'family',
              TextInput(
                label: 'Family (snake_case)',
                value: draft.family,
                problems: problems('family'),
                onChanged: (family) => edit((d) => d.copyWith(family: family)),
              ),
            ),
            a(
              'familyRank',
              NumberInput(
                label: 'Family rank (1 = easiest)',
                value: draft.familyRank,
                problems: problems('familyRank'),
                onChanged: (rank) => edit((d) => d.copyWith(familyRank: rank)),
              ),
            ),
            a(
              'popularity',
              NumberInput(
                label: 'Popularity (1 sorts first)',
                value: draft.popularity,
                problems: problems('popularity'),
                onChanged: (value) =>
                    edit((d) => d.copyWith(popularity: value)),
              ),
            ),
          ]),
        ],
      ),
      ExerciseEditorTab.classification => FormSection(
        title: tab.label,
        children: [
          FormRow([
            a(
              'loggingType',
              CodePicker<LoggingType>(
                label: 'Logging type',
                values: LoggingType.values,
                value: draft.loggingType,
                problems: problems('loggingType'),
                onChanged: (v) => edit((d) => d.copyWith(loggingType: v)),
              ),
            ),
            a(
              'mechanic',
              CodePicker<Mechanic>(
                label: 'Mechanic',
                values: Mechanic.values,
                value: draft.mechanic,
                problems: problems('mechanic'),
                onChanged: (v) => edit((d) => d.copyWith(mechanic: v)),
              ),
            ),
            a(
              'laterality',
              CodePicker<Laterality>(
                label: 'Laterality',
                values: Laterality.values,
                value: draft.laterality,
                problems: problems('laterality'),
                onChanged: (v) => edit((d) => d.copyWith(laterality: v)),
              ),
            ),
          ]),
          FormRow([
            a(
              'level',
              CodePicker<Level>(
                label: 'Level',
                values: Level.values,
                value: draft.level,
                problems: problems('level'),
                onChanged: (v) => edit((d) => d.copyWith(level: v)),
              ),
            ),
            a(
              'force',
              CodePicker<Force>(
                label: 'Force',
                values: Force.values,
                value: draft.force,
                problems: problems('force'),
                onChanged: (v) => edit((d) => d.copyWith(force: v)),
              ),
            ),
            a(
              'movementPattern',
              CodePicker<MovementPattern>(
                label: 'Movement pattern',
                values: MovementPattern.values,
                value: draft.movementPattern,
                problems: problems('movementPattern'),
                onChanged: (v) => edit((d) => d.copyWith(movementPattern: v)),
              ),
            ),
          ]),
          FormRow([
            a(
              'position',
              CodePicker<Position>(
                label: 'Position',
                values: Position.values,
                value: draft.position,
                problems: problems('position'),
                onChanged: (v) => edit((d) => d.copyWith(position: v)),
              ),
            ),
            a(
              'grip',
              CodePicker<Grip>(
                label: 'Grip (optional)',
                values: Grip.values,
                value: draft.grip,
                optional: true,
                problems: problems('grip'),
                onChanged: (v) => edit((d) => d.copyWith(grip: v)),
              ),
            ),
            a(
              'gripWidth',
              CodePicker<GripWidth>(
                label: 'Grip width (optional)',
                values: GripWidth.values,
                value: draft.gripWidth,
                optional: true,
                problems: problems('gripWidth'),
                onChanged: (v) => edit((d) => d.copyWith(gripWidth: v)),
              ),
            ),
          ]),
          FormRow([
            a(
              'defaultRestS',
              NumberInput(
                label: 'Default rest (s, $minRestS-$maxRestS)',
                value: draft.defaultRestS,
                problems: problems('defaultRestS'),
                onChanged: (v) => edit((d) => d.copyWith(defaultRestS: v)),
              ),
            ),
            if (draft.takesIncrement)
              a(
                'incrementKg',
                _DecimalInput(
                  label: 'Weight increment (kg)',
                  value: draft.incrementKg,
                  problems: problems('incrementKg'),
                  onChanged: (v) => edit((d) => d.copyWith(incrementKg: v)),
                ),
              )
            else
              const Text('No weight increment for this logging type.'),
          ]),
        ],
      ),
      ExerciseEditorTab.equipment => FormSection(
        title: tab.label,
        children: [
          a(
            'equipment',
            _CodeChips<Equipment>(
              label: 'Equipment (all needed together)',
              values: Equipment.values,
              selected: draft.equipment,
              problems: problems('equipment'),
              onChanged: (v) => edit((d) => d.copyWith(equipment: v)),
            ),
          ),
          a(
            'equipmentAlternatives',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.md,
              children: [
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
          ),
        ],
      ),
      ExerciseEditorTab.muscles => FormSection(
        title: tab.label,
        children: [
          a(
            'mainMuscles',
            _CodeChips<Muscle>(
              label: 'Main muscles (1-$maxMainMuscles)',
              values: Muscle.values,
              selected: draft.mainMuscles,
              problems: problems('mainMuscles'),
              onChanged: (v) => edit((d) => d.copyWith(mainMuscles: v)),
            ),
          ),
          a(
            'secondaryMuscles',
            _CodeChips<Muscle>(
              label: 'Secondary muscles (0-$maxSecondaryMuscles)',
              values: Muscle.values,
              selected: draft.secondaryMuscles,
              problems: problems('secondaryMuscles'),
              onChanged: (v) => edit((d) => d.copyWith(secondaryMuscles: v)),
            ),
          ),
        ],
      ),
      ExerciseEditorTab.alternatives => _alternatives(problems, edit),
      ExerciseEditorTab.text => FormSection(
        title: tab.label,
        children: [
          a(
            'l10n.en.aliases',
            _StringList(
              label: 'Aliases (0-$maxAliases)',
              values: draft.aliases,
              problems: problems('l10n.en.aliases'),
              onChanged: (v) => edit((d) => d.copyWith(aliases: v)),
            ),
          ),
          a(
            'l10n.en.setup',
            _StringList(
              label: 'Setup (${setupLines.min}-${setupLines.max})',
              values: draft.setup,
              problems: problems('l10n.en.setup'),
              onChanged: (v) => edit((d) => d.copyWith(setup: v)),
            ),
          ),
          a(
            'l10n.en.execution',
            _StringList(
              label: 'Execution (${executionLines.min}-${executionLines.max})',
              values: draft.execution,
              problems: problems('l10n.en.execution'),
              onChanged: (v) => edit((d) => d.copyWith(execution: v)),
            ),
          ),
          a(
            'l10n.en.mistakes',
            _StringList(
              label: 'Mistakes (${mistakeLines.min}-${mistakeLines.max})',
              values: draft.mistakes,
              problems: problems('l10n.en.mistakes'),
              onChanged: (v) => edit((d) => d.copyWith(mistakes: v)),
            ),
          ),
          a(
            'l10n.en.safety',
            TextInput(
              label: 'Safety (optional)',
              value: draft.safety ?? '',
              problems: problems('l10n.en.safety'),
              onChanged: (v) =>
                  edit((d) => d.copyWith(safety: v.isEmpty ? null : v)),
            ),
          ),
          a(
            'l10n.en.cues',
            _StringList(
              label: 'Cues (${cueLines.min}-${cueLines.max})',
              values: draft.cues,
              problems: problems('l10n.en.cues'),
              onChanged: (v) => edit((d) => d.copyWith(cues: v)),
            ),
          ),
        ],
      ),
      ExerciseEditorTab.generator => FormSection(
        title: tab.label,
        children: [
          a(
            'generatorTier',
            _TierRadios(
              value: draft.generatorTier,
              problems: problems('generatorTier'),
              onChanged: (v) => edit((d) => d.copyWith(generatorTier: v)),
            ),
          ),
          a(
            'stressAreas',
            _CodeChips<SensitiveArea>(
              label: 'Stress areas',
              helper:
                  'A user who marks one of these as sensitive never gets '
                  'this exercise.',
              values: SensitiveArea.values,
              selected: draft.stressAreas,
              problems: problems('stressAreas'),
              onChanged: (v) => edit((d) => d.copyWith(stressAreas: v)),
            ),
          ),
        ],
      ),
    };
  }

  Widget _alternatives(
    List<String> Function(String field) problems,
    void Function(ExerciseDraft Function(ExerciseDraft d) change) edit,
  ) {
    final draft = state.draft;
    final otherIds = [
      for (final record in state.library)
        if (record.id != draft.id) record.id,
    ]..sort();
    final names = {
      for (final record in state.library) record.id: record.draft.name,
    };
    return FormSection(
      title: 'Alternatives (overrides of the computed list)',
      children: [
        anchors.anchor(
          'pinnedAlternatives',
          _IdList(
            label: 'Pinned (shown first)',
            ids: draft.pinnedAlternatives,
            choices: otherIds,
            names: names,
            problems: problems('pinnedAlternatives'),
            onChanged: (v) => edit((d) => d.copyWith(pinnedAlternatives: v)),
          ),
        ),
        anchors.anchor(
          'excludedAlternatives',
          _IdList(
            label: 'Excluded (never shown)',
            ids: draft.excludedAlternatives,
            choices: otherIds,
            names: names,
            problems: problems('excludedAlternatives'),
            onChanged: (v) => edit((d) => d.copyWith(excludedAlternatives: v)),
          ),
        ),
      ],
    );
  }
}

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
    this.helper,
    this.onRemove,
    this.problems = const [],
  });

  final String label;

  /// A line under the label on what the choice does.
  final String? helper;
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
        if (helper case final helper?) _Helper(helper),
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

/// A muted line under a field's label.
class _Helper extends StatelessWidget {
  const _Helper(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted),
  );
}

/// The generator tier, one row per tier with its meaning; none is picked
/// while the exercise is not rated, and tapping the picked one clears it.
class _TierRadios extends StatelessWidget {
  const _TierRadios({
    required this.value,
    required this.onChanged,
    this.problems = const [],
  });

  final GeneratorTier? value;
  final ValueChanged<GeneratorTier?> onChanged;
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Generator tier', style: text.labelLarge),
        const _Helper(
          'How good this exercise is for a generated program, judged among '
          'exercises of its own equipment.',
        ),
        const SizedBox(height: Gap.xs),
        for (final tier in GeneratorTier.values)
          Semantics(
            selected: tier == value,
            child: InkWell(
              onTap: () => onChanged(tier == value ? null : tier),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  spacing: Gap.sm,
                  children: [
                    RadioMark(selected: tier == value),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(codeLabel(tier), style: text.labelLarge),
                          _Helper(_tierMeaning(tier)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (value == null) const _Helper('Not rated: counts as standard.'),
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
