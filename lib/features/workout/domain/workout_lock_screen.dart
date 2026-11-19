import 'package:forge_core/forge_core.dart';

/// The workout in progress as the lock screen shows it. Its times are
/// counted by the system, so they run without the app.
class LockScreenWorkout extends Equatable {
  const LockScreenWorkout({
    required this.name,
    required this.startedAt,
    this.current,
    this.set,
    this.rest,
  });

  final String name;

  /// The elapsed time counts up from it.
  final DateTime startedAt;

  /// The set to do now on one line, e.g. "Bench Press · set 2 of 3"; null
  /// when every set is done.
  final String? current;

  /// The same set in parts, where there is room for them (iOS); null when
  /// every set is done.
  final LockScreenSet? set;

  /// The running rest, shown instead of the workout until it ends.
  final RestCountdown? rest;

  @override
  List<Object?> get props => [name, startedAt, current, set, rest];
}

/// The set to do now in parts: its [exercise] large, the exercise's place
/// in the workout ([position], "Exercise 3 of 6"), the set and its values
/// ([line], "Set 2 of 3 · 80 kg × 8"), and one entry per set of the
/// exercise, true where it is done.
class LockScreenSet extends Equatable {
  const LockScreenSet({
    required this.exercise,
    required this.position,
    required this.line,
    required this.done,
  });

  final String exercise;
  final String position;
  final String line;
  final List<bool> done;

  @override
  List<Object?> get props => [exercise, position, line, done];
}

/// A running rest from [startsAt]: the system counts down to [endsAt].
class RestCountdown extends Equatable {
  const RestCountdown({
    required this.startsAt,
    required this.endsAt,
    required this.title,
    this.detail,
  });

  /// When the whole rest, time added included, began; what has passed of
  /// it is shown.
  final DateTime startsAt;
  final DateTime endsAt;
  final String title;

  /// What comes next, e.g. the next set; null when nothing is left.
  final String? detail;

  @override
  List<Object?> get props => [startsAt, endsAt, title, detail];
}

/// What a button on the lock screen does to the running rest.
enum LockScreenRestAction {
  /// −15 s.
  shorten,

  /// +15 s.
  extend,
  skip,
}

/// The workout in progress on the lock screen. iOS shows all of it, a Live
/// Activity from start to finish; Android only its rest, as an ongoing
/// notification. Silent: a rest's end is announced by the rest
/// notification alone.
abstract interface class WorkoutLockScreen {
  /// Shows [workout], replacing what is shown.
  Future<Result<void>> show(LockScreenWorkout workout);

  /// Removes what is shown, if anything.
  Future<Result<void>> clear();

  /// Taps on it that open the app, including the one that launched it; for
  /// one listener. None where a tap only opens the app (Android).
  Stream<void> taps();

  /// Its rest buttons pressed without opening the app, including those
  /// pressed while the app did not run; for one listener. None where it
  /// has no buttons (Android, iOS below 17).
  Stream<LockScreenRestAction> restActions();
}
