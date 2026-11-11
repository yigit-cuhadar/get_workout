import 'package:forge_core/forge_core.dart';

import '../../../core/grouping.dart';
import '../../settings/domain/user_settings.dart';
import 'workout.dart';

/// What "+15 s" adds to a running rest.
const restExtension = Duration(seconds: 15);

/// The rest of the workout in progress, kept with it on the device. It is
/// defined by when it ends on the device clock, never by counting, so it
/// survives backgrounding, minimizing and restarting the app.
class Rest extends Equatable {
  const Rest({required this.endsAt, this.after});

  final DateTime endsAt;

  /// The set whose tick started it, so unticking that set cancels it. Null
  /// once the workout's sets moved, since the reference would point at
  /// another set.
  final SetRef? after;

  bool runsAt(DateTime now) => endsAt.isAfter(now);

  Rest extendedBy(Duration duration) =>
      Rest(endsAt: endsAt.add(duration), after: after);

  Rest detached() => Rest(endsAt: endsAt);

  @override
  List<Object?> get props => [endsAt, after];
}

/// How long to rest after ticking set [ref] done; null for no rest.
///
/// Warm-ups start none. In a superset or circuit only the last item of the
/// round starts one: the group's last exercise that has a set at [ref]'s
/// position. The length is that of the group's last exercise (the one
/// itself outside a group), as the program estimates it: its program
/// rest, else [exerciseRestS] of its exercise, else the settings' default.
/// A rest of 0 means none.
Duration? restAfterTick(
  Workout workout,
  SetRef ref, {
  required RestTimerSettings settings,
  required int? Function(String exerciseId) exerciseRestS,
}) {
  if (!settings.enabled) return null;
  final exercises = workout.exercises;
  final set = exercises
      .elementAtOrNull(ref.exercise)
      ?.sets
      .elementAtOrNull(ref.set);
  if (set == null || set.isWarmup) return null;
  final (start, end) = groupRange(exercises, ref.exercise);
  final roundLast = [
    for (var i = start; i < end; i++)
      if (exercises[i].sets.length > ref.set) i,
  ].last;
  if (roundLast != ref.exercise) return null;
  final source = exercises[end - 1];
  final seconds =
      source.goal?.restS ??
      exerciseRestS(source.exerciseId) ??
      settings.defaultS;
  return seconds > 0 ? Duration(seconds: seconds) : null;
}

/// The first set not done yet in the order the workout is done in, after
/// [after] and then from the start; null when every set is done. Outside a
/// group that is set after set; a group goes round by round, each
/// exercise's next set in turn.
SetRef? nextSet(Workout workout, SetRef? after) {
  final exercises = workout.exercises;
  final order = [
    for (final (start, end) in groupBlocks(exercises))
      for (var round = 0; round < _rounds(exercises, start, end); round++)
        for (var i = start; i < end; i++)
          if (exercises[i].sets.length > round) (exercise: i, set: round),
  ];
  final at = after == null ? -1 : order.indexOf(after);
  return [
    ...order.skip(at + 1),
    ...order.take(at + 1),
  ].where((ref) => !exercises[ref.exercise].sets[ref.set].done).firstOrNull;
}

int _rounds(List<WorkoutExercise> exercises, int start, int end) =>
    [for (var i = start; i < end; i++) exercises[i].sets.length]
        .fold(0, (most, sets) => sets > most ? sets : most);
