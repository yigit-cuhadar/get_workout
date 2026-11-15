import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart' as editing;
import 'keep_visible.dart';
import 'widgets/exercise_card.dart';
import 'widgets/set_bubble.dart';
import 'widgets/set_type_menu.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// The sets of exercise [exercise] of the workout [editor] edits as
/// [SetBubble]s for its open card. Tapping a bubble selects its set;
/// long-pressing it opens the [SetTypeMenu]; the add bubble asks which kind
/// of set to add.
ExerciseCardSets setBubbles(
  BuildContext context,
  int exercise,
  EditedWorkout state,
  WorkoutEditor<EditedWorkout> editor,
) {
  final sets = state.workout!.exercises[exercise].sets;
  Widget bubble(int set) => _Bubble(
    ref: (exercise: exercise, set: set),
    state: state,
    editor: editor,
  );
  final full = sets.length >= WorkoutLimits.maxSets;
  return ExerciseCardSets(
    warmups: [
      for (final (i, s) in sets.indexed)
        if (s.isWarmup) bubble(i),
    ],
    working: [
      for (final (i, s) in sets.indexed)
        if (!s.isWarmup) bubble(i),
    ],
    add: SetBubble.add(
      semanticLabel: AppLocalizations.of(context).workoutAddSet,
      onTap: full ? null : () => addSetOfKind(context, editor, exercise),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.ref, required this.state, required this.editor});

  final SetRef ref;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    final selection = state.selection;
    final selected =
        selection?.exercise == ref.exercise && selection?.set == ref.set;
    final types = exercise.loggingType.setTypes;
    // The same as the set bar's options: see WorkoutEditor.setType.
    final actions = {
      for (final type in types)
        if (type != set.type)
          CustomSemanticsAction(
            label: l10n.workoutChangeSetType(l10n.setTypeLabel(type)),
          ): () =>
              editor.setType(ref, type),
      CustomSemanticsAction(label: l10n.workoutRemoveSet): () =>
          editor.removeSet(ref),
    };
    final bubble = Builder(
      builder: (context) => SetBubble(
        label: l10n.setLabel(exercise, ref.set),
        semanticLabel: l10n.setBubbleLabel(exercise, ref.set),
        done: set.done,
        selected: selected,
        warmup: set.isWarmup,
        onTap: () => editor.selectSet(ref),
        onLongPress: () => showSetTypeMenu(
          context: context,
          types: [
            for (final type in types)
              SetTypeMenuItem(
                label: l10n.setTypeLabel(type),
                bubble: _labelAs(l10n, exercise, ref.set, type),
                warmup: type == SetType.warmup,
                current: type == set.type,
                onTap: () => editor.setType(ref, type),
              ),
          ],
          removeLabel: l10n.workoutRemoveSet,
          onRemove: () => editor.removeSet(ref),
        ),
        actions: actions,
      ),
    );
    return selected ? KeepVisible(child: bubble) : bubble;
  }
}

/// The label set [index] of [exercise] would get as a set of [type], moved
/// where [editing.retypedSetPosition] puts it.
String _labelAs(
  AppLocalizations l10n,
  WorkoutExercise exercise,
  int index,
  SetType type,
) {
  final set = exercise.sets[index];
  if (set.type == type) return l10n.setLabel(exercise, index);
  final to = editing.retypedSetPosition(exercise, index, type);
  final retyped = exercise.copyWith(
    sets: [...exercise.sets]
      ..removeAt(index)
      ..insert(to, set.copyWith(type: type)),
  );
  return l10n.setLabel(retyped, to);
}
