import 'package:forge_core/forge_core.dart';

import '../../../core/grouping.dart';
import '../../settings/domain/user_settings.dart';
import 'workout.dart';

/// What "+15 s" adds to a running rest.
const restExtension = Duration(seconds: 15);

/// How far ahead a rest can end: the longest rest (600 s) plus room for
/// "+15 s". A rest ending later is not believed: a damaged file, or the
/// device clock set back.
const maxRestAhead = Duration(minutes: 30);

/// The rest of the workout in progress, kept with it on the device. It is
/// defined by when it ends on the device clock, never by counting, so it
/// survives backgrounding, minimizing and restarting the app.
class Rest extends Equatable {
  const Rest({required this.endsAt, this.after});

  final DateTime endsAt;

  /// The set whose tick started it, so unticking that set ends it. Null once
  /// an edit moved sets, since the position would point at another set.
  final SetRef? after;

  /// Running at [now]: not over, and not ending more than [maxRestAhead]
  /// later.
  bool runsAt(DateTime now) =>
      endsAt.isAfter(now) && !endsAt.isAfter(now.add(maxRestAhead));

  /// "+15 s", never past [maxRestAhead] from [now].
  Rest extendedAt(DateTime now) {
    final extended = endsAt.add(restExtension);
    final latest = now.add(maxRestAhead);
    return Rest(
      endsAt: extended.isAfter(latest) ? latest : extended,
      after: after,
    );
  }

  Rest detached() => Rest(endsAt: endsAt);

  /// This rest once an edit made [after]: unlinked when the edit
  /// [movesSets] (its set may now be elsewhere), else ended when its set
  /// is no longer done. An empty workout has no rest.
  Rest? followEdit(Workout after, {required bool movesSets}) {
    if (after.isEmpty) return null;
    final at = this.after;
    if (at == null) return this;
    if (movesSets) return detached();
    final set = after.exercises
        .elementAtOrNull(at.exercise)
        ?.sets
        .elementAtOrNull(at.set);
    return set != null && set.done ? this : null;
  }

  @override
  List<Object?> get props => [endsAt, after];
}

/// Whether [before] and [after] have the same exercises in the same order
/// with as many sets each, so a set's place means the same set in both.
bool sameShape(Workout before, Workout after) {
  final old = before.exercises;
  final now = after.exercises;
  if (old.length != now.length) return false;
  for (var i = 0; i < now.length; i++) {
    if (old[i].exerciseId != now[i].exerciseId ||
        old[i].sets.length != now[i].sets.length) {
      return false;
    }
  }
  return true;
}

/// The set [after] has ticked done that [before] had not, if the edit did
/// nothing else to the workout's shape.
SetRef? newlyDone(Workout before, Workout after) {
  if (!sameShape(before, after)) return null;
  final old = before.exercises;
  final now = after.exercises;
  for (var i = 0; i < now.length; i++) {
    for (var j = 0; j < now[i].sets.length; j++) {
      if (now[i].sets[j].done && !old[i].sets[j].done) {
        return (exercise: i, set: j);
      }
    }
  }
  return null;
}

/// How long to rest after ticking set [at] done; null for no rest.
///
/// Warm-ups start none. In a superset or circuit, rounds count working
/// sets (warm-ups are not in any round), and only the round's last item
/// starts a rest: the group's last exercise that has that many working
/// sets. The length is that of the group's last exercise (the one itself
/// outside a group), as the program estimates it: its program rest, else
/// [exerciseRestS] of its exercise, else the settings' default. A rest of
/// 0 means none.
Duration? restAfterTick(
  Workout workout,
  SetRef at, {
  required RestTimerSettings settings,
  required int? Function(String exerciseId) exerciseRestS,
}) {
  if (!settings.enabled) return null;
  final exercises = workout.exercises;
  final sets = exercises.elementAtOrNull(at.exercise)?.sets;
  final set = sets?.elementAtOrNull(at.set);
  if (sets == null || set == null || set.isWarmup) return null;
  final round = sets.take(at.set).where((s) => !s.isWarmup).length;
  final (start, end) = groupRange(exercises, at.exercise);
  final roundLast = [
    for (var i = start; i < end; i++)
      if (_working(exercises[i]).length > round) i,
  ].last;
  if (roundLast != at.exercise) return null;
  final source = exercises[end - 1];
  final seconds =
      source.goal?.restS ??
      exerciseRestS(source.exerciseId) ??
      settings.defaultS;
  return seconds > 0 ? Duration(seconds: seconds) : null;
}

/// The first set not done yet in the order the workout is done in, after
/// [after] and then from the start; null when every set is done. Outside a
/// group that is set after set. A group does its warm-ups first, exercise
/// by exercise, then goes round by round over the working sets, each
/// exercise's next one in turn.
SetRef? nextSet(Workout workout, SetRef? after) {
  final exercises = workout.exercises;
  final order = <SetRef>[];
  for (final (start, end) in groupBlocks(exercises)) {
    if (end - start == 1) {
      for (var j = 0; j < exercises[start].sets.length; j++) {
        order.add((exercise: start, set: j));
      }
      continue;
    }
    for (var i = start; i < end; i++) {
      for (final (j, set) in exercises[i].sets.indexed) {
        if (set.isWarmup) order.add((exercise: i, set: j));
      }
    }
    final working = [for (var i = start; i < end; i++) _working(exercises[i])];
    final rounds = working.fold(
      0,
      (most, w) => w.length > most ? w.length : most,
    );
    for (var round = 0; round < rounds; round++) {
      for (var i = start; i < end; i++) {
        final positions = working[i - start];
        if (positions.length > round) {
          order.add((exercise: i, set: positions[round]));
        }
      }
    }
  }
  final at = after == null ? -1 : order.indexOf(after);
  return [
    ...order.skip(at + 1),
    ...order.take(at + 1),
  ].where((ref) => !exercises[ref.exercise].sets[ref.set].done).firstOrNull;
}

/// The positions of [exercise]'s working (non-warm-up) sets.
List<int> _working(WorkoutExercise exercise) => [
  for (final (j, set) in exercise.sets.indexed)
    if (!set.isWarmup) j,
];

/// Whether [rest] is the one ticking [asked] started at [now]: its effort
/// question then has no time limit.
bool restStartedBy(Rest? rest, SetRef asked, DateTime now) =>
    rest != null && rest.after == asked && rest.runsAt(now);
