import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import 'cardio_session.dart';
import 'cardio_type.dart';

/// How far back the health store's workouts are read: the store's limit
/// for one call.
const healthCardioDays = 366;

/// The cardio type of a health store workout; null for strength work,
/// which is not cardio.
CardioType? cardioTypeOf(HealthWorkoutType type) => switch (type) {
  HealthWorkoutType.running => CardioType.outdoorRun,
  HealthWorkoutType.treadmillRunning => CardioType.treadmillRun,
  HealthWorkoutType.walking => CardioType.outdoorWalk,
  HealthWorkoutType.hiking => CardioType.hiking,
  HealthWorkoutType.cycling => CardioType.outdoorCycle,
  HealthWorkoutType.elliptical => CardioType.elliptical,
  HealthWorkoutType.rowing => CardioType.rowing,
  HealthWorkoutType.stairClimbing => CardioType.stairClimber,
  HealthWorkoutType.swimming => CardioType.swimming,
  HealthWorkoutType.jumpRope => CardioType.jumpRope,
  HealthWorkoutType.hiit => CardioType.hiit,
  HealthWorkoutType.other => CardioType.other,
  HealthWorkoutType.strength => null,
};

/// A health store workout as a session; its id keeps it apart from the
/// stored ones.
CardioSession? healthSession(HealthWorkout workout) {
  final type = cardioTypeOf(workout.type);
  if (type == null) return null;
  final meters = workout.distanceMeters;
  final kcal = workout.energyKcal;
  return CardioSession(
    id: 'health-${workout.id}',
    type: type,
    date: workout.start,
    duration: workout.duration,
    distanceKm: meters == null || meters <= 0 ? null : meters / 1000,
    calories: kcal == null || kcal <= 0 ? null : kcal.round(),
    avgHeartRate: workout.averageHeartRate,
    healthSource: workout.source,
  );
}

/// The cardio sessions the health store holds for the last
/// [healthCardioDays] days, newest first; none without a store or with
/// access refused (on iOS a refusal reads as none).
class GetHealthCardio implements UseCase<List<CardioSession>, NoParams> {
  GetHealthCardio(this._health, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final HealthSteps _health;
  final DateTime Function() _clock;

  @override
  Future<Result<List<CardioSession>>> call([
    NoParams params = const NoParams(),
  ]) async {
    switch (await _health.availability()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: HealthAvailability.available):
        break;
      case Ok():
        return const Ok([]);
    }
    switch (await _health.workoutsPermission()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: HealthPermission.denied):
        return const Ok([]);
      case Ok():
    }
    final now = _clock();
    final first = DateTime(now.year, now.month, now.day - healthCardioDays + 1);
    final read = await _health.workouts(first, now);
    return read.map(
      (workouts) => [
        for (final workout in workouts.reversed) ?healthSession(workout),
      ],
    );
  }
}
