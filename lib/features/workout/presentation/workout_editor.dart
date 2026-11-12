import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/grouping.dart' as grouping;
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/exercise_queries.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../settings/domain/retyped_weights.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/exercise_stats.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart' as editing;

/// What the exercise sections and set rows show of a workout being edited.
abstract interface class EditedWorkout {
  Workout? get workout;

  /// The stats of the workout's exercises that have arrived.
  Map<String, ExerciseStats?> get stats;

  /// A set that could not be ticked for missing or wrong values.
  SetRef? get invalidSet;

  /// What the set did last time; see [lastTimeSet].
  WorkoutSet? lastTime(SetRef ref);

  /// The values an empty field of the set shows, and takes when ticked.
  SetValues suggestion(SetRef ref);
}

/// Editing a workout's exercises and sets, shared by the workout in
/// progress and the editing of a stored one. Each change goes through
/// [edit], which decides whether the workout can be changed now.
mixin WorkoutEditor<S extends EditedWorkout> on Cubit<S> {
  /// Applies [change] to the workout, when it can be edited now.
  /// [movesSets] tells that sets may have moved or gone, so a reference
  /// to one held elsewhere may no longer point at it.
  void edit(Workout Function(Workout workout) change, {bool movesSets = false});

  /// Ticks the set done, or unticks it.
  void toggleDone(SetRef ref);

  /// The live exercises by id, for alternatives.
  Map<String, Exercise> get knownExercises;

  /// Keyed by set and drop (null for the set's own weight).
  final _retyped = RetypedWeights<(SetRef, int?)>();

  void setNote(String text) =>
      edit((workout) => workout.copyWith(note: () => _note(text)));

  /// Adds [exercises], named in [language], as many as fit; false when none
  /// was added.
  bool addExercises(List<Exercise> exercises, String language) {
    final count = state.workout?.exercises.length;
    _editExercises(
      (list) => [
        ...list,
        for (final exercise in exercises.take(
          WorkoutLimits.maxExercises - list.length,
        ))
          editing.exerciseFor(exercise, language),
      ],
    );
    return state.workout?.exercises.length != count;
  }

  void removeExercise(int index) => _editExercises(
    (list) => _has(list, index) ? grouping.removeItem(list, index) : list,
    movesSets: true,
  );

  void swapExercise(int index, Exercise exercise, String language) {
    _retyped.clear();
    _editExercise(index, (e) => editing.swapExercise(e, exercise, language));
  }

  /// [to] is where the exercise lands; see [grouping.moveItem].
  void moveExercise(int from, int to) => _editExercises(
    (list) => _has(list, from) && _has(list, to)
        ? grouping.moveItem(list, from, to)
        : list,
    movesSets: true,
  );

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

  /// A new empty set after the last one.
  void addSet(int index) => _editExercise(
    index,
    (e) => e.sets.length >= WorkoutLimits.maxSets
        ? e
        : e.copyWith(sets: [...e.sets, const WorkoutSet()]),
  );

  void removeSet(SetRef ref) => _editExercise(
    ref.exercise,
    (e) => _has(e.sets, ref.set)
        ? e.copyWith(sets: [...e.sets]..removeAt(ref.set))
        : e,
    movesSets: true,
  );

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

  void setToFailure(SetRef ref, bool toFailure) =>
      _editSet(ref, (set, _) => set.copyWith(toFailure: toFailure));

  /// Blank removes it.
  void setSetNote(SetRef ref, String text) =>
      _editSet(ref, (set, _) => set.copyWith(note: () => _note(text)));

  /// Reps in reserve; null clears it.
  void setRir(SetRef ref, int? rir) =>
      _editSet(ref, (set, _) => set.copyWith(rir: () => rir));

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

  /// Puts [set] in the place of [ref].
  void replaceSet(SetRef ref, WorkoutSet set) => _editExercise(
    ref.exercise,
    (e) => e.copyWith(
      sets: [for (final (i, s) in e.sets.indexed) i == ref.set ? set : s],
    ),
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
    replaceSet(ref, changed);
  }

  void _editExercise(
    int index,
    WorkoutExercise Function(WorkoutExercise exercise) change, {
    bool movesSets = false,
  }) => _editExercises(
    (list) => [for (final (i, e) in list.indexed) i == index ? change(e) : e],
    movesSets: movesSets,
  );

  void _editExercises(
    List<WorkoutExercise> Function(List<WorkoutExercise> list) change, {
    bool movesSets = false,
  }) {
    if (movesSets) _retyped.clear();
    edit(
      (workout) => workout.copyWith(exercises: change(workout.exercises)),
      movesSets: movesSets,
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
