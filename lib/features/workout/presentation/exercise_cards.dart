import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/grouping.dart';
import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import 'selected_set_view.dart';
import 'set_bubbles.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// The exercises of the workout [editor] edits, a card for each one or
/// each superset or circuit. Only the card of the selected set is open,
/// showing its sets as [EditedWorkout.setView] says; the others show each
/// exercise's progress on one line, and tapping one opens it. [picker] is
/// the route of the exercise picker above the page.
class ExerciseCards extends StatelessWidget {
  const ExerciseCards({
    super.key,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
  });

  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;

  /// Where an exercise's detail page opens above the page.
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final exercises = state.workout!.exercises;
    final open = state.selection?.exercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (start, end) in groupBlocks(exercises))
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (end - start > 1)
                  ListTile(
                    dense: true,
                    title: Text(
                      l10n.groupLabel(exercises[start].group!, end - start),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (open != null && open >= start && open < end) ...[
                  for (var i = start; i < end; i++)
                    _OpenHeader(
                      index: i,
                      state: state,
                      editor: editor,
                      picker: picker,
                      exerciseRoute: exerciseRoute,
                    ),
                  switch (state.setView) {
                    SetView.bubbles => SetBubbles(
                      start: start,
                      end: end,
                      state: state,
                      editor: editor,
                    ),
                    SetView.selectedSet => SelectedSetView(
                      start: start,
                      end: end,
                      state: state,
                      editor: editor,
                    ),
                  },
                ] else
                  for (var i = start; i < end; i++)
                    ListTile(
                      leading: _groupLeading(exercises, i),
                      title: Text(
                        l10n.workoutExerciseProgress(
                          exercises[i].name,
                          exercises[i].doneSets.length,
                          exercises[i].sets.length,
                        ),
                      ),
                      trailing: _ExerciseMenu(
                        index: i,
                        state: state,
                        editor: editor,
                        picker: picker,
                        exerciseRoute: exerciseRoute,
                      ),
                      onTap: () => editor.openExercise(i),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget? _groupLeading(List<WorkoutExercise> exercises, int index) =>
    exercises[index].group == null
    ? null
    : CircleAvatar(child: Text(groupItemLabel(exercises, index)));

/// An exercise of the open card: its name, goal, last time and note, a way
/// to its detail page, and its menu. Within a group, tapping it moves the
/// selection to it.
class _OpenHeader extends StatelessWidget {
  const _OpenHeader({
    required this.index,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
  });

  final int index;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;

  /// Where an exercise's detail page opens above the page.
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    final last = state.stats[exercise.exerciseId]?.last;
    final details = [
      ?l10n.goalText(exercise, unit),
      if (last != null) l10n.lastTimeText(last.date),
      ?exercise.note,
    ];
    final grouped = exercise.group != null;
    return ListTile(
      leading: _groupLeading(exercises, index),
      title: Text(exercise.name, style: theme.textTheme.titleMedium),
      subtitle: details.isEmpty ? null : Text(details.join('\n')),
      selected: grouped && state.selection?.exercise == index,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.workoutExerciseDetails,
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push(exerciseRoute(exercise.exerciseId)),
          ),
          _ExerciseMenu(
            index: index,
            state: state,
            editor: editor,
            picker: picker,
            exerciseRoute: exerciseRoute,
          ),
        ],
      ),
      onTap: grouped ? () => editor.openExercise(index) : null,
    );
  }
}

enum _ExerciseAction { details, swap, link, ungroup, note, remove }

/// The actions on exercise [index]: its detail page, swap, group, note,
/// remove.
class _ExerciseMenu extends StatelessWidget {
  const _ExerciseMenu({
    required this.index,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
  });

  final int index;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;

  /// Where an exercise's detail page opens above the page.
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    return PopupMenuButton<_ExerciseAction>(
      tooltip: l10n.programItemActions,
      onSelected: (action) => switch (action) {
        _ExerciseAction.details => context.push(
          exerciseRoute(exercise.exerciseId),
        ),
        _ExerciseAction.swap => _swap(context),
        _ExerciseAction.link => editor.linkWithNext(index),
        _ExerciseAction.ungroup => editor.ungroup(index),
        _ExerciseAction.note => _editNote(context, exercise),
        _ExerciseAction.remove => _remove(context, exercise),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ExerciseAction.details,
          child: Text(l10n.workoutExerciseDetails),
        ),
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
        if (exercise.group != null)
          PopupMenuItem(
            value: _ExerciseAction.ungroup,
            child: Text(l10n.programUngroup),
          ),
        PopupMenuItem(
          value: _ExerciseAction.note,
          child: Text(
            exercise.note == null ? l10n.workoutAddNote : l10n.workoutEditNote,
          ),
        ),
        PopupMenuItem(
          value: _ExerciseAction.remove,
          child: Text(l10n.programRemoveItem),
        ),
      ],
    );
  }

  /// The exercise's alternatives first, then the whole library.
  Future<void> _swap(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final owned = context.read<EquipmentCubit>().state.owned ?? const {};
    final alternatives = editor.alternatives(index, owned).take(8).toList();
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
      editor.swapExercise(index, replacement, language);
    }
  }

  Future<void> _editNote(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
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
    if (saved == true) editor.setExerciseNote(index, controller.text);
    controller.dispose();
  }

  Future<void> _remove(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
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
    editor.removeExercise(index);
  }
}
