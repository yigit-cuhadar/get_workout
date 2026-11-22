import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
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
import '../../shell/page_header.dart';
import '../../shell/problem_card.dart';
import '../../shell/save_bar.dart';
import '../../shell/status_tag.dart';
import 'access_tag.dart';
import 'program_editor_cubit.dart';

/// Every field outside the days the form has an input for, by its short
/// name in the problem card.
final programEditorFields = <String, String>{
  'id': 'Id',
  'order': 'Order',
  'premium': 'Premium',
  'level': 'Level',
  'goal': 'Goal',
  'equipmentProfile': 'Equipment profile',
  'lengthWeeks': 'Length in weeks',
  for (final language in languages) ...{
    'l10n.$language.name': 'Name (${language.toUpperCase()})',
    'l10n.$language.summary': 'Summary (${language.toUpperCase()})',
  },
  'days': 'Days',
};

/// A field of a day (`days[0].name`) or of one of its exercises
/// (`days[0].items[1].sets`).
final _dayField = RegExp(r'^days\[(\d+)\](?:\.items\[(\d+)\])?(?:\.(\w+))?$');

/// The short name of a day's [field] in the problem card, or null when it
/// is not a day's.
String? _dayFieldLabel(String field) {
  final match = _dayField.firstMatch(field);
  if (match == null) return null;
  final day = 'Day ${int.parse(match[1]!) + 1}';
  return switch ((match[2], match[3])) {
    (final String item, _) => '$day, exercise ${int.parse(item) + 1}',
    (null, 'name') => '$day name',
    (null, 'items') => '$day exercises',
    _ => day,
  };
}

/// Where a problem of [field] leads, most precise first: the field, then
/// its exercise's row, then its day.
List<String> _anchorsOf(String field) {
  final match = _dayField.firstMatch(field);
  if (match == null) return [field];
  final day = 'days[${match[1]}]';
  return [field, if (match[2] case final item?) '$day.items[$item]', day];
}

/// The width of the summary panel on the right of the form.
const _summaryWidth = 300.0;

/// Creates a ready-made program ([id] null) or edits one: its card, its
/// text, and its days with their exercises as table rows, with the values
/// computed from the days in a panel on the right. The catalogue rules'
/// problems are summed up at the top and shown under the fields they
/// concern.
class ProgramEditorPage extends StatelessWidget {
  const ProgramEditorPage({super.key, required this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ProgramEditorCubit>(param1: id),
    child: const _EditorView(),
  );
}

class _EditorView extends StatefulWidget {
  const _EditorView();

  @override
  State<_EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<_EditorView> {
  final _anchors = FieldAnchors();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _anchors.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the problem card at the top of the form into view.
  void _showProblems() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Brings the input of [field] into view, or the nearest one shown.
  void _open(String field) {
    final shown = _anchorsOf(field).where(_anchors.shows).firstOrNull;
    if (shown != null) _anchors.open(shown);
  }

  void _show(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _toList() => context.go(AdminRoutes.programs);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProgramEditorCubit, ProgramEditorState>(
      listenWhen: (previous, state) =>
          previous.status != state.status ||
          (previous.problems.isEmpty && state.problems.isNotEmpty),
      listener: (context, state) {
        switch (state.status) {
          case EditorStatus.saved:
            _show('Saved as ${codeLabel(state.draft.status)}.');
            // A new program gets its own address once it exists.
            if (GoRouterState.of(context).matchedLocation ==
                AdminRoutes.newProgram) {
              context.go(AdminRoutes.program(state.draft.id));
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
            _showProblems();
          default:
        }
      },
      builder: (context, state) {
        final cubit = context.read<ProgramEditorCubit>();
        if (state.status == EditorStatus.loadFailed) {
          return Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: _toList)),
            body: ErrorView(
              title: "Couldn't load the program",
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
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: maxFormWidth + Gap.md + _summaryWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Gap.md,
                  children: [
                    PageHeader(
                      back: ('Programs', _toList),
                      title: stored == null
                          ? 'New program'
                          : stored.draft
                                .textOf(CatalogueProgram.fallbackLanguage)
                                .name,
                      subtitle: stored == null
                          ? 'Not saved yet'
                          : '${stored.id} · last saved '
                                '${dateTimeLabel(stored.version.card)}',
                      trailing: [
                        if (stored != null) ...[
                          StatusTag(stored.draft.status),
                          AccessTag(premium: stored.draft.premium),
                        ],
                        if (state.isDirty)
                          const ForgeTag(
                            'Unsaved changes',
                            kind: ForgeTagKind.category,
                          ),
                      ],
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Gap.md,
                        children: [
                          Expanded(
                            child: _Form(
                              state: state,
                              scroll: _scroll,
                              anchors: _anchors,
                              onOpen: _open,
                            ),
                          ),
                          SizedBox(
                            width: _summaryWidth,
                            child: SingleChildScrollView(
                              child: _Summary(state: state),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SaveBar(
                      noun: 'program',
                      liveEffect: "It appears in every user's catalogue.",
                      hiddenEffect:
                          "It leaves every user's catalogue; copies users "
                          'already made stay theirs.',
                      stored: stored?.draft.status,
                      dirty: state.isDirty,
                      saving: state.status == EditorStatus.saving,
                      canSave: state.canSave,
                      onSave: cubit.save,
                      onSaveAs: cubit.saveAs,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The card, the text and the days, under the blocking problems.
class _Form extends StatelessWidget {
  const _Form({
    required this.state,
    required this.scroll,
    required this.anchors,
    required this.onOpen,
  });

  final ProgramEditorState state;
  final ScrollController scroll;
  final FieldAnchors anchors;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProgramEditorCubit>();
    final draft = state.draft;
    List<String> problems(String field) => state.problemsFor(field);
    final a = anchors.anchor;

    // The list stays when the fields are rebuilt, so the scroll does.
    return ListView(
      controller: scroll,
      children: [
        if (state.status == EditorStatus.changedSinceLoaded)
          MaterialBanner(
            content: const Text(
              'This program changed since you opened it, so your save '
              'was refused. Reload it (your changes here are lost) and '
              'make them again.',
            ),
            actions: [
              TextButton(onPressed: cubit.reload, child: const Text('Reload')),
            ],
          ),
        if (state.problems.isNotEmpty) ...[
          ProblemCard(
            lines: [
              for (final problem in state.problems)
                (
                  label:
                      programEditorFields[problem.field] ??
                      _dayFieldLabel(problem.field) ??
                      problem.field,
                  message: problem.message,
                  onOpen:
                      programEditorFields.containsKey(problem.field) ||
                          _dayField.hasMatch(problem.field)
                      ? () => onOpen(problem.field)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
        ],
        // A replaced draft, or days and items added, moved or removed,
        // rebuild every field.
        KeyedSubtree(
          key: ValueKey(state.formVersion),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                title: 'Card',
                children: [
                  FormRow([
                    a(
                      'id',
                      TextInput(
                        label:
                            'Id (pr_ + snake_case; cannot change once saved)',
                        value: draft.id,
                        enabled: state.isNew,
                        problems: problems('id'),
                        onChanged: (id) =>
                            cubit.change((d) => d.copyWith(id: id)),
                      ),
                    ),
                    a(
                      'order',
                      NumberInput(
                        label: 'Order in the catalogue (1 first, unique)',
                        value: draft.order,
                        problems: problems('order'),
                        onChanged: (order) =>
                            cubit.change((d) => d.copyWith(order: order)),
                      ),
                    ),
                  ]),
                  a(
                    'premium',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Premium'),
                          subtitle: const Text(
                            'Only users with premium can read its days.',
                          ),
                          value: draft.premium,
                          onChanged: (premium) =>
                              cubit.change((d) => d.copyWith(premium: premium)),
                        ),
                        FieldProblems(problems('premium')),
                      ],
                    ),
                  ),
                  FormRow([
                    a(
                      'level',
                      CodePicker<Level>(
                        label: 'Level',
                        values: Level.values,
                        value: draft.level,
                        problems: problems('level'),
                        onChanged: (v) =>
                            cubit.change((d) => d.copyWith(level: v)),
                      ),
                    ),
                    a(
                      'goal',
                      CodePicker<Goal>(
                        label: 'Goal',
                        values: Goal.values,
                        value: draft.goal,
                        problems: problems('goal'),
                        onChanged: (v) =>
                            cubit.change((d) => d.copyWith(goal: v)),
                      ),
                    ),
                    a(
                      'equipmentProfile',
                      CodePicker<EquipmentProfile>(
                        label: 'Equipment profile (every exercise fits it)',
                        values: EquipmentProfile.values,
                        value: draft.equipmentProfile,
                        problems: problems('equipmentProfile'),
                        onChanged: (v) => cubit.change(
                          (d) => d.copyWith(equipmentProfile: v),
                        ),
                      ),
                    ),
                  ]),
                  a(
                    'lengthWeeks',
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
                  ),
                ],
              ),
              for (final language in languages)
                FormSection(
                  title: 'Text (${language.toUpperCase()})',
                  children: [
                    a(
                      'l10n.$language.name',
                      TextInput(
                        label:
                            'Name (1-${ProgramLimits.maxNameLength} '
                            'characters, unique)',
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
                    ),
                    a(
                      'l10n.$language.summary',
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
                    ),
                  ],
                ),
              for (final (index, _) in draft.days.indexed)
                anchors.anchor(
                  'days[$index]',
                  _DaySection(state: state, day: index, anchors: anchors),
                ),
              a(
                'days',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
      ],
    );
  }
}

/// What is stored on the card but computed from the days, and the numbers
/// the catalogue rules hold the program to; beside the form, always in
/// view.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final ProgramEditorState state;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final content = state.content;
    final summary = state.summary;
    final minutes = content['minutes'];
    final equipment = content['equipment']! as List<String>;
    final band = weeklySetBands[state.draft.level];
    final warnings = state.warnings;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            Text('Summary', style: text.titleMedium),
            Text(
              'Computed from the days, stored on the card on save.',
              style: muted,
            ),
            _Fact('Days per week', '${content['daysPerWeek']}'),
            _Fact(
              'Minutes',
              minutes is Map ? '${minutes['min']}-${minutes['max']}' : '-',
            ),
            if (minutes is Map)
              Text(
                'Per day: ${summary.minutesPerDay.join(', ')}',
                style: muted,
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.xs,
              children: [
                Text('Equipment', style: muted),
                Text(equipment.isEmpty ? '-' : equipment.join(', ')),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.xs,
              children: [
                Text(
                  [
                    'Weekly sets',
                    if (band != null) '${band.min}-${band.max} for this level',
                  ].join(' · '),
                  style: muted,
                ),
                for (final muscle in majorMuscles)
                  _MuscleSets(
                    muscle: muscle,
                    sets: summary.weeklySets[muscle] ?? 0,
                    band: band,
                  ),
              ],
            ),
            if (warnings.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(style.radii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Gap.xs,
                    children: [
                      for (final warning in warnings)
                        Text(
                          'Warning: $warning',
                          style: text.bodyMedium?.copyWith(
                            color: colors.onAccentSoft,
                          ),
                        ),
                      Text(
                        'Warnings never block a save; a focus or '
                        'equipment-limited program says why in its summary.',
                        style: text.bodySmall?.copyWith(
                          color: colors.onAccentSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A computed value with its name on the left.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = ForgeStyle.of(context).colors.inkMuted;
    return Row(
      spacing: Gap.sm,
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: muted)),
        ),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

/// A major muscle's weekly sets, marked when outside its level's band.
class _MuscleSets extends StatelessWidget {
  const _MuscleSets({
    required this.muscle,
    required this.sets,
    required this.band,
  });

  final Muscle muscle;
  final double sets;
  final ({int min, int max})? band;

  @override
  Widget build(BuildContext context) {
    final band = this.band;
    final outside = band != null && (sets < band.min || sets > band.max);
    final value = Theme.of(context).textTheme.labelLarge;
    return Row(
      children: [
        Expanded(child: Text(codeLabel(muscle))),
        Text(
          formatSets(sets),
          style: outside
              ? value?.copyWith(
                  color: ForgeStyle.of(context).colors.onAccentSoft,
                )
              : value,
        ),
      ],
    );
  }
}

/// Widths of the fixed columns of a day's exercise table.
const _indexWidth = 24.0;
const _numberWidth = 64.0;
const _targetWidth = 2 * _numberWidth + Gap.lg;
const _bracketWidth = 3.0;

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.state,
    required this.day,
    required this.anchors,
  });

  final ProgramEditorState state;
  final int day;
  final FieldAnchors anchors;

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
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    return FormSection(
      title: 'Day ${day + 1}',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: anchors.anchor(
                '$field.name',
                TextInput(
                  label:
                      'Name (1-${ProgramLimits.maxDayNameLength} characters)',
                  value: days[day].name,
                  problems: state.problemsFor('$field.name'),
                  onChanged: (name) => cubit.renameDay(day, name),
                ),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isNotEmpty) const _ItemHeader(),
            for (final (index, _) in items.indexed)
              anchors.anchor(
                '$field.items[$index]',
                _ItemRow(state: state, day: day, item: index, anchors: anchors),
              ),
            FieldProblems([
              ...state.problemsFor(field),
              ...state.problemsFor('$field.items'),
            ]),
          ],
        ),
        Text(
          'Sets ${ProgramLimits.minSets}-${ProgramLimits.maxSets} · reps '
          'from–to, or a duration of ${ProgramLimits.minDurationS}-'
          '${ProgramLimits.maxDurationS} s for a timed exercise · rest '
          '0-${ProgramLimits.maxRestS} s. The link joins an exercise with the '
          'next (a superset; three or more make a circuit).',
          style: muted,
        ),
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

/// Lays out one line of a day's exercise table: the superset bracket's
/// room, then the columns.
class _ItemCells extends StatelessWidget {
  const _ItemCells({
    required this.index,
    required this.exercise,
    required this.sets,
    required this.target,
    required this.rest,
    required this.actions,
  });

  final Widget index;
  final Widget exercise;
  final Widget sets;
  final Widget target;
  final Widget rest;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _bracketWidth + Gap.sm),
      child: Row(
        spacing: Gap.sm,
        children: [
          SizedBox(width: _indexWidth, child: index),
          Expanded(child: exercise),
          SizedBox(width: _numberWidth, child: sets),
          SizedBox(width: _targetWidth, child: target),
          SizedBox(width: _numberWidth, child: rest),
          actions,
        ],
      ),
    );
  }
}

class _ItemHeader extends StatelessWidget {
  const _ItemHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: _ItemCells(
        index: Text('#', style: style),
        exercise: Text('Exercise', style: style),
        sets: Text('Sets', style: style),
        target: Text('Reps or time (s)', style: style),
        rest: Text('Rest (s)', style: style),
        // The actions' room, so the columns line up with the rows.
        actions: const Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _Actions(),
        ),
      ),
    );
  }
}

/// One exercise of a day as a table row; a bracket on its left joins the
/// rows of a superset or circuit.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.state,
    required this.day,
    required this.item,
    required this.anchors,
  });

  final ProgramEditorState state;
  final int day;
  final int item;
  final FieldAnchors anchors;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProgramEditorCubit>();
    final colors = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final items = state.draft.days[day].items;
    final value = items[item];
    final field = 'days[$day].items[$item]';
    final exercise = state.exercises[value.exerciseId]?.draft;
    final timed = exercise?.loggingType?.isDurationBased ?? false;
    void edit(ProgramItem Function(ProgramItem item) change) =>
        cubit.changeItem(day, item, change);
    final group = value.group;
    final groupSize = items.where((i) => group != null && i.group == group);
    bool sameGroup(int other) =>
        group != null &&
        other >= 0 &&
        other < items.length &&
        items[other].group == group;
    final a = anchors.anchor;

    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: _ItemCells(
            index: Text('${item + 1}', style: muted),
            exercise: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise?.name ?? 'Unknown exercise',
                  style: text.labelLarge,
                ),
                Text(
                  [
                    value.exerciseId,
                    if (exercise != null &&
                        exercise.status != ExerciseStatus.live)
                      codeLabel(exercise.status),
                    if (exercise?.loggingType case final type?) codeLabel(type),
                    if (group != null)
                      '${groupSize.length > 2 ? 'Circuit' : 'Superset'} '
                          '$group',
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
            sets: a(
              '$field.sets',
              _CellNumber(
                hint: 'Sets',
                value: value.sets < 0 ? null : value.sets,
                onChanged: (v) => edit((i) => i.copyWith(sets: v ?? -1)),
              ),
            ),
            // A target the exercise does not take shows while it is set,
            // so it can be cleared.
            target: Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!timed || value.repMin != null || value.repMax != null) ...[
                  SizedBox(
                    key: const ValueKey('repMin'),
                    width: _numberWidth,
                    child: a(
                      '$field.repMin',
                      _CellNumber(
                        hint: 'From',
                        value: value.repMin,
                        onChanged: (v) =>
                            edit((i) => i.copyWith(repMin: () => v)),
                      ),
                    ),
                  ),
                  Text('–', style: muted),
                  SizedBox(
                    key: const ValueKey('repMax'),
                    width: _numberWidth,
                    child: _CellNumber(
                      hint: 'To',
                      value: value.repMax,
                      onChanged: (v) =>
                          edit((i) => i.copyWith(repMax: () => v)),
                    ),
                  ),
                ],
                if (timed || value.durationS != null)
                  SizedBox(
                    key: const ValueKey('durationS'),
                    width: _numberWidth,
                    child: a(
                      '$field.durationS',
                      _CellNumber(
                        hint: 'Time',
                        value: value.durationS,
                        onChanged: (v) =>
                            edit((i) => i.copyWith(durationS: () => v)),
                      ),
                    ),
                  ),
              ],
            ),
            rest: a(
              '$field.restS',
              _CellNumber(
                hint: 'Rest',
                value: value.restS < 0 ? null : value.restS,
                onChanged: (v) => edit((i) => i.copyWith(restS: v ?? -1)),
              ),
            ),
            actions: _Actions(
              onUp: item == 0
                  ? null
                  : () => cubit.moveItem(day, item, item - 1),
              onDown: item == items.length - 1
                  ? null
                  : () => cubit.moveItem(day, item, item + 1),
              onLink: canLinkWithNext(items, item)
                  ? () => cubit.linkWithNext(day, item)
                  : null,
              onUngroup: group == null ? null : () => cubit.ungroup(day, item),
              onRemove: () => cubit.removeItem(day, item),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _bracketWidth + Gap.sm),
          child: FieldProblems(state.problemsWithin(field)),
        ),
      ],
    );
    if (group == null) return row;
    // The bracket runs on into the next row of the group and stops short of
    // the group's ends.
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          width: _bracketWidth,
          top: sameGroup(item - 1) ? 0 : Gap.sm,
          bottom: sameGroup(item + 1) ? 0 : Gap.sm,
          child: ColoredBox(color: colors.inkSubtle),
        ),
      ],
    );
  }
}

/// What a row's exercise can do: move, join the next, leave its group,
/// go. A null action is off.
class _Actions extends StatelessWidget {
  const _Actions({
    this.onUp,
    this.onDown,
    this.onLink,
    this.onUngroup,
    this.onRemove,
  });

  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLink;
  final VoidCallback? onUngroup;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    Widget action(String tooltip, IconData icon, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          icon: Icon(icon),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action('Move up', Icons.arrow_upward, onUp),
        action('Move down', Icons.arrow_downward, onDown),
        action('Link with the next (superset or circuit)', Icons.link, onLink),
        action('Ungroup', Icons.link_off, onUngroup),
        action('Remove', Icons.close, onRemove),
      ],
    );
  }
}

/// A whole number in a table cell; anything else reads as unset, which the
/// rules report.
class _CellNumber extends StatelessWidget {
  const _CellNumber({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  /// The column's name, shown while empty.
  final String hint;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      decoration: InputDecoration(isDense: true, hintText: hint),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (text) => onChanged(int.tryParse(text)),
    );
  }
}
