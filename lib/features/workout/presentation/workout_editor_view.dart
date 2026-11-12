import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/grouping.dart';
import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/workout.dart';
import 'workout_editor.dart';
import 'workout_set_row.dart';
import 'workout_text.dart';

/// Asks [title] with [body]; true when the user picks [confirm].
Future<bool> confirmChoice(
  BuildContext context, {
  required String title,
  required String? body,
  required String cancel,
  required String confirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}

enum _ExerciseAction { swap, link, ungroup, note, remove }

/// Exercise [index] of the workout [editor] edits: its name, goal, last
/// time and note, its actions, then its sets. [picker] is the route of the
/// exercise picker above the page.
class ExerciseSection extends StatelessWidget {
  const ExerciseSection({
    super.key,
    required this.index,
    required this.state,
    required this.editor,
    required this.picker,
    required this.unit,
    required this.effort,
  });

  final int index;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;
  final WeightUnit unit;
  final EffortScale effort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = editor;
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    final group = exercise.group;
    final (start, end) = groupRange(exercises, index);
    final last = state.stats[exercise.exerciseId]?.last;
    final details = [
      ?l10n.goalText(exercise, unit),
      if (last != null) l10n.lastTimeText(last.date),
      ?exercise.note,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group == null || index == start) const Divider(),
        if (group != null && index == start)
          ListTile(
            dense: true,
            title: Text(
              l10n.groupLabel(group, end - start),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ListTile(
          leading: group == null ? null : CircleAvatar(child: Text(group)),
          title: Text(exercise.name, style: theme.textTheme.titleMedium),
          subtitle: details.isEmpty ? null : Text(details.join('\n')),
          trailing: PopupMenuButton<_ExerciseAction>(
            tooltip: l10n.programItemActions,
            onSelected: (action) => switch (action) {
              _ExerciseAction.swap => _swap(context),
              _ExerciseAction.link => cubit.linkWithNext(index),
              _ExerciseAction.ungroup => cubit.ungroup(index),
              _ExerciseAction.note => _editNote(context, exercise),
              _ExerciseAction.remove => _remove(context, exercise),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _ExerciseAction.swap,
                child: Text(l10n.workoutSwap),
              ),
              if (canLinkWithNext(exercises, index))
                PopupMenuItem(
                  value: _ExerciseAction.link,
                  child: Text(
                    linkedSize(exercises, index) == 2
                        ? l10n.programMakeSuperset
                        : l10n.programMakeCircuit,
                  ),
                ),
              if (group != null)
                PopupMenuItem(
                  value: _ExerciseAction.ungroup,
                  child: Text(l10n.programUngroup),
                ),
              PopupMenuItem(
                value: _ExerciseAction.note,
                child: Text(
                  exercise.note == null
                      ? l10n.workoutAddNote
                      : l10n.workoutEditNote,
                ),
              ),
              PopupMenuItem(
                value: _ExerciseAction.remove,
                child: Text(l10n.programRemoveItem),
              ),
            ],
          ),
        ),
        SetHeading(type: exercise.loggingType, unit: unit),
        for (final (s, _) in exercise.sets.indexed)
          SetRow(
            ref: (exercise: index, set: s),
            state: state,
            editor: editor,
            unit: unit,
            effort: effort,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.workoutAddSet),
              onPressed: exercise.sets.length >= WorkoutLimits.maxSets
                  ? null
                  : () => cubit.addSet(index),
            ),
          ),
        ),
      ],
    );
  }

  /// The exercise's alternatives first, then the whole library.
  Future<void> _swap(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = editor;
    final language = Localizations.localeOf(context).languageCode;
    final owned = context.read<EquipmentCubit>().state.owned ?? const {};
    final alternatives = cubit.alternatives(index, owned).take(8).toList();
    const browse = Object();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.workoutSwapBrowse),
              onTap: () => Navigator.pop(context, browse),
            ),
            if (alternatives.isNotEmpty)
              ListTile(
                dense: true,
                title: Text(
                  l10n.workoutSwapAlternatives,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            for (final exercise in alternatives)
              ListTile(
                title: Text(exercise.localized(context).name),
                subtitle: Text(
                  l10n.exerciseSummary(
                    l10n.muscleNames(exercise.mainMuscles),
                    l10n.equipmentNames(exercise.equipment),
                  ),
                ),
                onTap: () => Navigator.pop(context, exercise),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    var replacement = choice is Exercise ? choice : null;
    if (identical(choice, browse)) {
      final picked = await context.push<List<Exercise>>(
        picker(max: 1, multiple: false),
      );
      replacement = picked?.firstOrNull;
    }
    if (replacement != null) {
      cubit.swapExercise(index, replacement, language);
    }
  }

  Future<void> _editNote(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
    final cubit = editor;
    final controller = TextEditingController(text: exercise.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exercise.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            maxLengthFormatter(WorkoutLimits.maxExerciseNoteLength),
          ],
          decoration: InputDecoration(labelText: l10n.workoutExerciseNote),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.programSave),
          ),
        ],
      ),
    );
    if (saved == true) cubit.setExerciseNote(index, controller.text);
    controller.dispose();
  }

  Future<void> _remove(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
    final cubit = editor;
    if (exercise.doneSets.isNotEmpty &&
        !await confirmChoice(
          context,
          title: l10n.workoutRemoveExerciseTitle,
          body: null,
          cancel: l10n.cancel,
          confirm: l10n.programRemoveItem,
        )) {
      return;
    }
    cubit.removeExercise(index);
  }
}

/// The exercises of the workout [editor] edits by name, reordered by
/// dragging; groups move as one.
class ReorderSheet extends StatelessWidget {
  const ReorderSheet({super.key, required this.editor});

  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<WorkoutEditor<EditedWorkout>, EditedWorkout>(
      bloc: editor,
      buildWhen: (previous, current) =>
          previous.workout?.exercises != current.workout?.exercises,
      builder: (context, state) {
        final exercises = state.workout?.exercises ?? const [];
        return SafeArea(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: exercises.length,
            onReorderItem: editor.moveExercise,
            itemBuilder: (context, index) {
              final exercise = exercises[index];
              return ListTile(
                key: ValueKey(index),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    semanticLabel: l10n.programReorder,
                  ),
                ),
                title: Text(exercise.name),
                trailing: exercise.group == null ? null : Text(exercise.group!),
              );
            },
          ),
        );
      },
    );
  }
}

/// A multi-line note that applies every change at once.
class NoteField extends StatefulWidget {
  const NoteField({
    super.key,
    required this.initial,
    required this.label,
    required this.maxLength,
    required this.onChanged,
  });

  final String? initial;
  final String label;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  State<NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<NoteField> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: null,
    textCapitalization: TextCapitalization.sentences,
    inputFormatters: [maxLengthFormatter(widget.maxLength)],
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}
