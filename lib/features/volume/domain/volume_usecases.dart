import '../../programs/domain/calendar_date.dart';
import '../../workout/domain/history_usecases.dart';
import 'weekly_volume.dart';

/// [weeks] weeks ending with the one starting on [lastWeek]; see
/// [volumeWeeks] for [muscles].
typedef VolumeQuery = ({
  String uid,
  CalendarDate lastWeek,
  int weeks,
  Map<String, ExerciseMuscles> muscles,
});

/// The weekly sets per muscle of the [VolumeQuery]'s weeks, oldest first,
/// again on every change of their workouts. The volume page reads
/// [trendWeeks]; one week is the Today tab's card.
class WatchWeeklyVolume {
  const WatchWeeklyVolume(this._watchWorkouts);
  final WatchWorkoutsBetween _watchWorkouts;

  Stream<List<WeekVolume>> call(VolumeQuery query) {
    final first = query.lastWeek.addDays(
      -DateTime.daysPerWeek * (query.weeks - 1),
    );
    return _watchWorkouts(
      query.uid,
      first,
      query.lastWeek.addDays(DateTime.daysPerWeek - 1),
    ).map(
      (workouts) => volumeWeeks(
        workouts,
        first: first,
        count: query.weeks,
        muscles: query.muscles,
      ),
    );
  }
}
