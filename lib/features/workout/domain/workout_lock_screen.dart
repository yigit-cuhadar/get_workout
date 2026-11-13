import 'package:forge_core/forge_core.dart';

/// The workout in progress as the lock screen shows it. Its times are
/// counted by the system, so they run without the app.
class LockScreenWorkout extends Equatable {
  const LockScreenWorkout({
    required this.name,
    required this.startedAt,
    this.current,
    this.rest,
  });

  final String name;

  /// The elapsed time counts up from it.
  final DateTime startedAt;

  /// The set to do now, e.g. "Bench Press · set 2 of 3"; null when every set
  /// is done.
  final String? current;

  /// The running rest, shown instead of the workout until it ends.
  final RestCountdown? rest;

  @override
  List<Object?> get props => [name, startedAt, current, rest];
}

/// A running rest: the system counts down to [endsAt].
class RestCountdown extends Equatable {
  const RestCountdown({required this.endsAt, required this.title, this.detail});

  final DateTime endsAt;
  final String title;

  /// What comes next, e.g. the next set; null when nothing is left.
  final String? detail;

  @override
  List<Object?> get props => [endsAt, title, detail];
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
}
