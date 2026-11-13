import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/grouping.dart' as grouping;
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/exercise_queries.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../settings/domain/retyped_weights.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/effort.dart';
import '../domain/exercise_stats.dart';
import '../domain/set_logging.dart';
import '../domain/set_selection.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart' as editing;

/// How the open exercise shows its sets. Two are tried for now; one goes
/// once the owner has picked.
enum SetView {
  /// A bubble per set.
  bubbles,

  /// The selected set only, with arrows to the others.
  selectedSet,
}

/// What the exercise cards and the set bar show of a workout being edited.
abstract interface class EditedWorkout {
  Workout? get workout;

  /// The open exercise and selected set as last picked or moved by an edit;
  /// null follows the next set to do. See [EditedSelection.selection].
  SetSelection? get picked;

  SetView get setView;

  /// The stats of the workout's exercises that have arrived.
  Map<String, ExerciseStats?> get stats;

  /// A set that could not be ticked for missing or wrong values.
  SetRef? get invalidSet;

  /// What the set did last time; see [lastTimeSet].
  WorkoutSet? lastTime(SetRef ref);

  /// The values an empty field of the set shows, and takes when ticked.
  SetValues suggestion(SetRef ref);
}

extension EditedSelection on EditedWorkout {
  /// What is open and selected now; see [resolveSelection].
  SetSelection? get selection => resolveSelection(workout, picked);
}

/// Editing a workout's exercises and sets, shared by the workout in
/// progress and the editing of a stored one. Each change goes through
/// [edit], which decides whether the workout can be changed now. The
/// selection follows every change: see `set_selection.dart`.
mixin WorkoutEditor<S extends EditedWorkout> on Cubit<S> {
  /// Applies [change] to the workout, when it can be edited now, with the
  /// selection [select] gives for the changed workout (unchanged without
  /// it). [movesSets] tells that sets may have moved or gone, so a
  /// reference to one held elsewhere may no longer point at it.
  void edit(
    Workout Function(Workout workout) change, {
    bool movesSets = false,
    SetSelection? Function(Workout after)? select,
  });

  /// Emits the state with [picked] or [setView] changed where given.
  void emitSelection({SetSelection? Function()? picked, SetView? setView});

  /// Ticks the set done, or unticks it.
  void toggleDone(SetRef ref);

  /// The live exercises by id, for alternatives.
  Map<String, Exercise> get knownExercises;

  /// Keyed by set and drop (null for the set's own weight).
  final _retyped = RetypedWeights<(SetRef, int?)>();

  void toggleSetView() => emitSelection(
    setView: state.setView == SetView.bubbles
        ? SetView.selectedSet
        : SetView.bubbles,
  );

  void selectSet(SetRef ref) {
    if (hasSet(ref)) emitSelection(picked: () => ref);
  }

  /// Opens exercise [index]: see [openedExercise].
  void openExercise(int index) {
    final workout = state.workout;
    if (workout != null && _has(workout.exercises, index)) {
      emitSelection(picked: () => openedExercise(workout, index));
    }
  }

  /// Moves the selection [by] sets within its exercise.
  void stepSet(int by) {
    final workout = state.workout;
    final current = state.selection;
    if (workout != null && current != null) {
      emitSelection(picked: () => stepSelection(workout, current, by));
    }
  }

  void setNote(String text) =>
      edit((workout) => workout.copyWith(note: () => _note(text)));

  /// Adds [exercises], named in [language], as many as fit; false when none
  /// was added.
  bool addExercises(List<Exercise> exercises, String language) {
    final before = state.workout;
    final current = state.selection;
    _editExercises(
      (list) => [
        ...list,
        for (final exercise in exercises.take(
          WorkoutLimits.maxExercises - list.length,
        ))
          editing.exerciseFor(exercise, language),
      ],
      select: (after) => before == null
          ? null
          : selectionAfterExercisesAdded(before, after, current),
    );
    return state.workout?.exercises.length != before?.exercises.length;
  }

  void removeExercise(int index) {
    final current = state.selection;
    _editExercises(
      (list) => _has(list, index) ? grouping.removeItem(list, index) : list,
      movesSets: true,
      select: (_) => selectionAfterExerciseRemoved(current, index),
    );
  }

  void swapExercise(int index, Exercise exercise, String language) {
    _retyped.clear();
    _editExercise(index, (e) => editing.swapExercise(e, exercise, language));
  }

  /// [to] is where the exercise lands; see [grouping.moveItem].
  void moveExercise(int from, int to) {
    final before = state.workout?.exercises;
    final current = state.selection;
    if (before == null || !_has(before, from) || !_has(before, to)) return;
    _editExercises(
      (list) => grouping.moveItem(list, from, to),
      movesSets: true,
      select: (_) => selectionAfterExerciseMoved(before, current, from, to),
    );
  }

  void linkWithNext(int index) => _editExercises(
    (list) => _has(list, index) && grouping.canLinkWithNext(list, index)
        ? grouping.linkWithNext(list, index)
        : list,
  );

  void ungroup(int index) => _editExercises(
    (list) => _has(list, index) ? grouping.ungroup(list, index) : list,
  );

  /// What could replace exercise [index], best first; empty when it is no
  /// longer in the library. [owned] is the user's equipment.
  List<Exercise> alternatives(int index, Set<Equipment> owned) {
    final exercises = knownExercises;
    final id = state.workout?.exercises.elementAtOrNull(index)?.exerciseId;
    final exercise = exercises[id];
    return exercise == null
        ? const []
        : alternativesFor(exercise, exercises.values, owned: owned);
  }

  void setExerciseNote(int index, String text) =>
      _editExercise(index, (e) => e.copyWith(note: () => _note(text)));

  /// A new empty set of [type] where [editing.newSetPosition] puts it,
  /// selected. Only rep-based exercises have drop sets; a duration one gets
  /// a normal set.
  void addSet(int index, SetType type) {
    final exercise = state.workout?.exercises.elementAtOrNull(index);
    if (exercise == null || exercise.sets.length >= WorkoutLimits.maxSets) {
      return;
    }
    final kind = type == SetType.drop && !exercise.loggingType.logsReps
        ? SetType.normal
        : type;
    final at = editing.newSetPosition(exercise, kind);
    _editExercise(
      index,
      (e) => e.copyWith(sets: [...e.sets]..insert(at, WorkoutSet(type: kind))),
      // A warm-up before other sets moves them.
      movesSets: at < exercise.sets.length,
      select: (_) => (exercise: index, set: at),
    );
  }

  void removeSet(SetRef ref) {
    final current = state.selection;
    _editExercise(
      ref.exercise,
      (e) => _has(e.sets, ref.set)
          ? e.copyWith(sets: [...e.sets]..removeAt(ref.set))
          : e,
      movesSets: true,
      select: (after) => selectionAfterSetRemoved(after, current, ref),
    );
  }

  /// [text] is in [unit]; blank clears it. See [RetypedWeights].
  void setWeight(SetRef ref, String text, WeightUnit unit) => _editSet(
    ref,
    (set, _) => set.copyWith(
      weightKg: () => _retyped.kg((ref, null), text, unit, set.weightKg),
    ),
  );

  void setReps(SetRef ref, String text) =>
      _editSet(ref, (set, _) => set.copyWith(reps: () => _whole(text)));

  /// In seconds.
  void setDuration(SetRef ref, String text) =>
      _editSet(ref, (set, _) => set.copyWith(durationS: () => _whole(text)));

  /// Leaving [SetType.drop] removes the drops; only rep-based exercises have
  /// drop sets.
  void setType(SetRef ref, SetType type) => _editSet(
    ref,
    (set, loggingType) => type == SetType.drop && !loggingType.logsReps
        ? set
        : set.copyWith(
            type: type,
            drops: type == SetType.drop ? set.drops : const [],
          ),
  );

  /// Blank removes it.
  void setSetNote(SetRef ref, String text) =>
      _editSet(ref, (set, _) => set.copyWith(note: () => _note(text)));

  /// Null clears it.
  void setEffort(SetRef ref, EffortStep? step) =>
      _editSet(ref, (set, _) => set.withEffort(step));

  void addDrop(SetRef ref) => _editSet(
    ref,
    (set, _) =>
        set.type != SetType.drop || set.drops.length >= WorkoutLimits.maxDrops
        ? set
        : set.copyWith(drops: [...set.drops, const Drop()]),
  );

  void removeDrop(SetRef ref, int drop) {
    _retyped.clear();
    _editSet(
      ref,
      (set, _) => _has(set.drops, drop)
          ? set.copyWith(drops: [...set.drops]..removeAt(drop))
          : set,
    );
  }

  /// [text] is in [unit]; blank clears it. See [RetypedWeights].
  void setDropWeight(SetRef ref, int drop, String text, WeightUnit unit) =>
      _editDrop(
        ref,
        drop,
        (d) => d.copyWith(
          weightKg: () => _retyped.kg((ref, drop), text, unit, d.weightKg),
        ),
      );

  void setDropReps(SetRef ref, int drop, String text) =>
      _editDrop(ref, drop, (d) => d.copyWith(reps: () => _whole(text)));

  /// Whether the workout has the set [ref].
  bool hasSet(SetRef ref) =>
      state.workout?.exercises
          .elementAtOrNull(ref.exercise)
          ?.sets
          .elementAtOrNull(ref.set) !=
      null;

  /// Existing set [ref] ticked done with its empty values taken from
  /// [EditedWorkout.suggestion], or unticked; null when it still lacks
  /// values and cannot be ticked.
  WorkoutSet? toggledSet(SetRef ref) {
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    return set.done
        ? set.copyWith(done: false)
        : completeSet(set, exercise.loggingType, state.suggestion(ref));
  }

  /// Puts [toggled] (see [toggledSet]) in the place of [ref]; ticked done,
  /// the next set to do is selected, see [selectionAfterTick], else [ref].
  void applyToggled(SetRef ref, WorkoutSet toggled) => _replaceSet(
    ref,
    toggled,
    select: (after) => toggled.done ? selectionAfterTick(after, ref) : ref,
  );

  void _replaceSet(
    SetRef ref,
    WorkoutSet set, {
    SetSelection? Function(Workout after)? select,
  }) => _editExercise(
    ref.exercise,
    (e) => e.copyWith(
      sets: [for (final (i, s) in e.sets.indexed) i == ref.set ? set : s],
    ),
    select: select,
  );

  void _editDrop(SetRef ref, int drop, Drop Function(Drop drop) change) =>
      _editSet(
        ref,
        (set, _) => _has(set.drops, drop)
            ? set.copyWith(
                drops: [
                  for (final (i, d) in set.drops.indexed)
                    i == drop ? change(d) : d,
                ],
              )
            : set,
      );

  /// A done set that the change leaves invalid is no longer done.
  void _editSet(
    SetRef ref,
    WorkoutSet Function(WorkoutSet set, LoggingType type) change,
  ) {
    final exercise = state.workout?.exercises.elementAtOrNull(ref.exercise);
    final set = exercise?.sets.elementAtOrNull(ref.set);
    if (exercise == null || set == null) return;
    final type = exercise.loggingType;
    var changed = change(set, type);
    if (changed.done && validateSet(changed, type).isNotEmpty) {
      changed = changed.copyWith(done: false);
    }
    _replaceSet(ref, changed);
  }

  void _editExercise(
    int index,
    WorkoutExercise Function(WorkoutExercise exercise) change, {
    bool movesSets = false,
    SetSelection? Function(Workout after)? select,
  }) => _editExercises(
    (list) => [for (final (i, e) in list.indexed) i == index ? change(e) : e],
    movesSets: movesSets,
    select: select,
  );

  void _editExercises(
    List<WorkoutExercise> Function(List<WorkoutExercise> list) change, {
    bool movesSets = false,
    SetSelection? Function(Workout after)? select,
  }) {
    if (movesSets) _retyped.clear();
    edit(
      (workout) => workout.copyWith(exercises: change(workout.exercises)),
      movesSets: movesSets,
      select: select,
    );
  }

  static bool _has(List<Object?> list, int index) =>
      index >= 0 && index < list.length;

  static String? _note(String text) => text.trim().isEmpty ? null : text;

  static int? _whole(String text) {
    final value = int.tryParse(text.trim());
    // Text fields cap the length; this guards pasted text.
    return value == null || value.abs() > 1000000 ? null : value;
  }
}
