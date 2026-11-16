import 'package:flutter_test/flutter_test.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/health_cardio.dart';

void main() {
  final now = DateTime(2026, 11, 13, 20);
  HealthWorkout run(String id, DateTime start, {HealthWorkoutType? type}) =>
      HealthWorkout(
        id: id,
        type: type ?? HealthWorkoutType.running,
        start: start,
        duration: const Duration(minutes: 29),
        distanceMeters: 5200,
        energyKcal: 309.6,
        averageHeartRate: 151,
        source: 'Watch',
      );

  test('a workout becomes a read-only session with its values', () {
    final session = healthSession(run('x', DateTime(2026, 11, 10, 7)))!;
    expect(session.id, 'health-x');
    expect(session.type, CardioType.outdoorRun);
    expect(session.distanceKm, 5.2);
    expect(session.calories, 310);
    expect(session.avgHeartRate, 151);
    expect(session.fromHealth, isTrue);
  });

  test('strength work is no cardio', () {
    expect(
      healthSession(run('s', now, type: HealthWorkoutType.strength)),
      isNull,
    );
    expect(cardioTypeOf(HealthWorkoutType.cycling), CardioType.outdoorCycle);
  });

  test('reads the store newest first', () async {
    final health = FakeHealthSteps(
      workoutsPermissionStatus: HealthPermission.granted,
      workoutList: [
        run('a', DateTime(2026, 11, 2, 7)),
        run('b', DateTime(2026, 11, 10, 7)),
        run('c', DateTime(2026, 11, 11, 7), type: HealthWorkoutType.strength),
      ],
      clock: () => now,
    );
    final result = await GetHealthCardio(health, clock: () => now)();
    expect(result.valueOrNull!.map((s) => s.id), ['health-b', 'health-a']);
  });

  test('no store or no access reads as none', () async {
    final unsupported = FakeHealthSteps(status: HealthAvailability.unsupported);
    expect((await GetHealthCardio(unsupported)()).valueOrNull, isEmpty);
    final refused = FakeHealthSteps(workoutList: [run('a', now)]);
    expect((await GetHealthCardio(refused)()).valueOrNull, isEmpty);
  });
}
