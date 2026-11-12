import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/completed_days.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';

/// The program days done, from the workouts started from them: a day is
/// done on the local date its workout started.
class WorkoutCompletedDays implements CompletedDays {
  const WorkoutCompletedDays(this._repository);

  final WorkoutRepository _repository;

  @override
  Stream<List<CompletedDay>> watch(
    String uid,
    String programId, {
    required CalendarDate from,
    required CalendarDate to,
  }) => _repository
      .watchWorkoutsBetween(uid, from: from, to: to)
      .map((workouts) => completedDaysOf(workouts, programId));
}
