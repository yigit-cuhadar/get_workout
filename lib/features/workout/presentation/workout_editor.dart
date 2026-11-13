import 'dart:async';

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
import '../domain/warmups.dart';
import '../domain/workout_editing.dart' as editing;

/// What the exercise cards and the set bar show of a workout being edited.
abstract interface class EditedWorkout {
  Workout? get workout;

  /// The open exercise and selected set as last picked or moved by an edit;
  /// null follows the next set to do. See [EditedSelection.selection].
  SetSelection? get picked;

  /// The working set just ticked whose effort the set bar asks, until it
  /// is answered or skipped, any set is picked, sets move, or
  /// [effortQuestionTime] passes; see [questionSet].
  SetRef? get asking;

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

  /// The set the set bar asks the effort of instead of showing the selected
  /// set; see [questionSet].
  SetRef? get questionRef => questionSet(workout, asking);

  /// The set whose effort row shows under the selected set's values; see
  /// [effortRowSet].
  SetRef? get effortRowRef => effortRowSet(workout, selection);
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

  /// Whether [edit] changes the workout now.
  bool get canEdit;

  /// Emits the state with [picked] as the selection; any pick ends the
  /// effort question ([EditedWorkout.asking]).
  void emitPicked(SetSelection? picked);

  /// Whether ticking a working set asks its effort; see
  /// [EditedWorkout.asking].
  bool get asksEffort;

  /// Emits the state with [asking] as [EditedWorkout.asking].
  void emitAsking(SetRef? asking);

  /// Notes that warm-ups were added to the workout automatically.
  void noteWarmupsAdded();

  /// Ticks the set done, or unticks it.
  void toggleDone(SetRef ref);

  /// The live exercises by id, for alternatives.
  Map<String, Exercise> get knownExercises;

  /// Whether exercises added or swapped in start [withWarmups].
  bool get addsWarmups;

  /// Keyed by set and drop (null for the set's own weight).
  final _retyped = RetypedWeights<(SetRef, int?)>();

  /// How long the set bar asks the effort of a set just ticked when left
  /// alone.
  static const effortQuestionTime = Duration(seconds: 10);

  /// Ends the effort question after [effortQuestionTime].
  Timer? _questionTimer;

  /// Asks the effort of [ref], or of none, for [effortQuestionTime].
  void _ask(SetRef? ref) {
    _questionTimer?.cancel();
    _questionTimer = null;
    if (state.asking != ref) emitAsking(ref);
    if (ref != null) {
      _questionTimer = Timer(effortQuestionTime, () {
        if (!isClosed && state.asking == ref) emitAsking(null);
      });
    }
  }

  /// The user is answering the effort question: it waits another
  /// [effortQuestionTime].
  void keepAsking() {
    final asking = state.asking;
    if (asking != null) _ask(asking);
  }

  /// Leaves the effort question unanswered.
  void skipEffort() => _ask(null);

  @override
  Future<void> close() {
    _questionTimer?.cancel();
    return super.close();
  }

  void selectSet(SetRef ref) {
    if (hasSet(ref)) emitPicked(ref);
  }

  /// Opens exercise [index]: see [openedExercise].
  void openExercise(int index) {
    final workout = state.workout;
    if (workout != null && _has(workout.exercises, index)) {
      emitPicked(openedExercise(workout, index));
    }
  }

  void setNote(String text) =>
      edit((workout) => workout.copyWith(note: () => _note(text)));

  /// Adds [exercises], named in [language], as many as fit; false when none
  /// was added.
  bool addExercises(List<Exercise> exercises, String language) {
    final before = state.workout;
    final current = state.selection;
    final room = WorkoutLimits.maxExercises - (before?.exercises.length ?? 0);
    final added = [
      for (final exercise in exercises.take(room))
        _warmedUp(editing.exerciseFor(exercise, language)),
    ];
    _editExercises(
      (list) => [...list, ...added],
      select: (after) => before == null
          ? null
          : selectionAfterExercisesAdded(before, after, current),
    );
    final changed = state.workout?.exercises.length != before?.exercises.length;
    if (changed && added.any((e) => e.sets.any((set) => set.isWarmup))) {
      noteWarmupsAdded();
    }
    return changed;
  }

  void removeExercise(int index) {
    final current = state.selection;
    _editExercises(
      (list) => _has(list, index) ? grouping.removeItem(list, index) : list,
      movesSets: true,
      select: (_) => selectionAfterExerciseRemoved(current, index),
    );
  }

  /// Its untouched warm-ups go when the new exercise takes none (see
  /// [withoutUnusedWarmups]); one without a done set gets warm-ups as one
  /// added would. When that changes its sets, it opens on its first undone.
  void swapExercise(int index, Exercise exercise, String language) {
    final before = state.workout?.exercises.elementAtOrNull(index);
    if (before == null || !canEdit) return;
    final swapped = editing.swapExercise(before, exercise, language);
    final kept = withoutUnusedWarmups(before, swapped);
    final fitted = before.doneSets.isEmpty ? _warmedUp(kept) : kept;
    final resized = fitted.sets.length != swapped.sets.length;
    final current = state.selection;
    _retyped.clear();
    _editExercise(
      index,
      (_) => fitted,
      movesSets: resized,
      select: (after) => resized && current?.exercise == index
          ? openedExercise(after, index)
          : current,
    );
    if (fitted.sets.length > kept.sets.length) noteWarmupsAdded();
  }

  WorkoutExercise _warmedUp(WorkoutExercise exercise) =>
      addsWarmups ? withWarmups(exercise) : exercise;

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

  /// Moves the exercise or group that is block [from] of
  /// [grouping.groupBlocks] so it becomes block [to].
  void moveBlock(int from, int to) {
    final exercises = state.workout?.exercises;
    if (exercises == null) return;
    final blocks = grouping.groupBlocks(exercises);
    if (!_has(blocks, from) || !_has(blocks, to)) return;
    // A block's first exercise moved onto another block's first exercise
    // moves it whole, before or after that block.
    moveExercise(blocks[from].$1, blocks[to].$1);
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
  /// drop sets. A set that becomes or stops being a warm-up moves where
  /// [editing.retypedSetPosition] puts it, the selection following it.
  void setType(SetRef ref, SetType type) {
    final exercise = state.workout?.exercises.elementAtOrNull(ref.exercise);
    final set = exercise?.sets.elementAtOrNull(ref.set);
    if (exercise == null ||
        set == null ||
        set.type == type ||
        (type == SetType.drop && !exercise.loggingType.logsReps)) {
      return;
    }
    final changed = _checked(
      set.copyWith(
        type: type,
        drops: type == SetType.drop ? set.drops : const [],
      ),
      exercise.loggingType,
    );
    final to = editing.retypedSetPosition(exercise, ref.set, type);
    final current = state.selection;
    _editExercise(
      ref.exercise,
      (e) => e.copyWith(
        sets: [...e.sets]
          ..removeAt(ref.set)
          ..insert(to, changed),
      ),
      movesSets: to != ref.set,
      select: (_) => selectionAfterSetMoved(current, ref, to),
    );
  }

  /// Blank removes it.
  void setSetNote(SetRef ref, String text) =>
      _editSet(ref, (set, _) => set.copyWith(note: () => _note(text)));

  /// Null clears it. Answers the effort question about [ref].
  void setEffort(SetRef ref, EffortStep? step) {
    _editSet(ref, (set, _) => set.withEffort(step));
    if (state.asking == ref) _ask(null);
  }

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
  /// A working set ticked done is asked its effort where [asksEffort].
  void applyToggled(SetRef ref, WorkoutSet toggled) {
    if (!canEdit) return;
    _replaceSet(
      ref,
      toggled,
      select: (after) => toggled.done ? selectionAfterTick(after, ref) : ref,
    );
    _ask(asksEffort && toggled.done && !toggled.isWarmup ? ref : null);
  }

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
    _replaceSet(ref, _checked(change(set, type), type));
  }

  /// [set], no longer done when it is not valid for [type].
  static WorkoutSet _checked(WorkoutSet set, LoggingType type) =>
      set.done && validateSet(set, type).isNotEmpty
      ? set.copyWith(done: false)
      : set;

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
