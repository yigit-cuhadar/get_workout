import '../../../core/grouping.dart';
import 'rest.dart';
import 'workout.dart';

/// The exercise open while a workout is logged and its selected set; [set]
/// is null while the exercise has no set.
typedef SetSelection = ({int exercise, int? set});

/// What is selected in [workout]: [picked] while it still points into it,
/// else the next set to do (see [nextSet]), else the first exercise opened
/// as [openedExercise] opens it; null without exercises.
SetSelection? resolveSelection(Workout? workout, SetSelection? picked) {
  if (workout == null || workout.exercises.isEmpty) return null;
  if (picked != null && _points(workout, picked)) return picked;
  return nextSet(workout, null) ?? openedExercise(workout, 0);
}

bool _points(Workout workout, SetSelection selection) {
  final sets = workout.exercises.elementAtOrNull(selection.exercise)?.sets;
  if (sets == null) return false;
  final set = selection.set;
  return set == null ? sets.isEmpty : set >= 0 && set < sets.length;
}

/// Exercise [index] opened: its first set not done, else its last.
SetSelection openedExercise(Workout workout, int index) {
  final sets = workout.exercises[index].sets;
  final undone = sets.indexWhere((set) => !set.done);
  return (
    exercise: index,
    set: undone >= 0
        ? undone
        : sets.isEmpty
        ? null
        : sets.length - 1,
  );
}

/// After [ticked] was ticked done in [workout]: the next set to do, in the
/// order supersets and circuits go round in, which opens the next exercise
/// once this one is done; [ticked] itself when every set is done.
SetSelection selectionAfterTick(Workout workout, SetRef ticked) =>
    nextSet(workout, ticked) ?? ticked;

/// After set [moved] was moved to position [to] of its exercise: [current]
/// where its set went.
SetSelection? selectionAfterSetMoved(
  SetSelection? current,
  SetRef moved,
  int to,
) {
  final set = current?.set;
  if (current == null || set == null || current.exercise != moved.exercise) {
    return current;
  }
  if (set == moved.set) return (exercise: current.exercise, set: to);
  final without = set > moved.set ? set - 1 : set;
  return (
    exercise: current.exercise,
    set: without >= to ? without + 1 : without,
  );
}

/// After set [removed] was removed: [current] where it moved to, or, when
/// it was the removed one, the set that took its place, else the one
/// before it, else none of the emptied exercise.
SetSelection? selectionAfterSetRemoved(
  Workout after,
  SetSelection? current,
  SetRef removed,
) {
  final set = current?.set;
  if (current == null || set == null || current.exercise != removed.exercise) {
    return current;
  }
  if (set < removed.set) return current;
  if (set > removed.set) return (exercise: current.exercise, set: set - 1);
  final count = after.exercises[removed.exercise].sets.length;
  return (
    exercise: current.exercise,
    set: count == 0 ? null : (set < count ? set : count - 1),
  );
}

/// After exercise [removed] was removed: [current] where it moved to; null,
/// the next set to do, when it was the removed one.
SetSelection? selectionAfterExerciseRemoved(
  SetSelection? current,
  int removed,
) {
  if (current == null || current.exercise == removed) return null;
  return current.exercise < removed
      ? current
      : (exercise: current.exercise - 1, set: current.set);
}

/// After the exercise at [from] of [before] was moved to [to] as
/// [moveItem] moves it (a group moving as one): [current] where its
/// exercise went.
SetSelection? selectionAfterExerciseMoved(
  List<WorkoutExercise> before,
  SetSelection? current,
  int from,
  int to,
) {
  if (current == null) return null;
  final moved = moveItem(
    [for (final (i, exercise) in before.indexed) _Position(i, exercise.group)],
    from,
    to,
  );
  return (
    exercise: moved.indexWhere((p) => p.index == current.exercise),
    set: current.set,
  );
}

/// After exercises were added to [before], making [after]: the first one
/// added opened when [before] had no set left to do, else [current].
SetSelection? selectionAfterExercisesAdded(
  Workout before,
  Workout after,
  SetSelection? current,
) {
  final added = before.exercises.length;
  if (after.exercises.length == added || nextSet(before, null) != null) {
    return current;
  }
  return openedExercise(after, added);
}

/// An exercise's place before a move, carried through it.
class _Position implements Groupable<_Position> {
  const _Position(this.index, this.group);

  final int index;
  @override
  final String? group;

  @override
  _Position withGroup(String? group) => _Position(index, group);
}

/// Whether [ref] is a done working set of [workout]: one that has an
/// effort (warm-ups are not rated).
bool _rated(Workout? workout, SetRef ref) {
  final set = workout?.exercises
      .elementAtOrNull(ref.exercise)
      ?.sets
      .elementAtOrNull(ref.set);
  return set != null && set.done && !set.isWarmup;
}

/// The set the set bar asks the effort of, in place of the selected set's
/// values: [asking] (the working set just ticked) while it is still done,
/// when its tick started no rest ([withRest] false); with a rest the rest
/// strip asks instead, see [restQuestionSet].
SetRef? questionSet(
  Workout? workout,
  SetRef? asking, {
  required bool withRest,
}) => !withRest && asking != null && _rated(workout, asking) ? asking : null;

/// The set the rest strip asks the effort of at [now]: [asking] while it is
/// still done and the rest its tick started ([withRest]) is still its own
/// ([rest] after it, so "+15 s" keeps it) and runs; it goes with the rest.
SetRef? restQuestionSet(
  Workout? workout,
  SetRef? asking, {
  required bool withRest,
  required Rest? rest,
  required DateTime now,
}) =>
    withRest &&
        asking != null &&
        _rated(workout, asking) &&
        restStartedBy(rest, asking, now)
    ? asking
    : null;

/// The set whose effort row the set bar shows under its values: the
/// selected set when it is done and not a warm-up; never an undone set.
SetRef? effortRowSet(Workout? workout, SetSelection? selection) {
  final index = selection?.set;
  if (selection == null || index == null) return null;
  final ref = (exercise: selection.exercise, set: index);
  return _rated(workout, ref) ? ref : null;
}
