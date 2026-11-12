import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import '../workout/fixtures.dart';

/// [id] working the given muscles, as stored with a workout.
WorkoutExercise worked(
  String id,
  List<WorkoutSet> sets, {
  List<Muscle> main = const [Muscle.pec],
  List<Muscle> secondary = const [],
}) => WorkoutExercise(
  exerciseId: id,
  name: 'Stored $id',
  loggingType: LoggingType.weightReps,
  mainMuscles: main,
  secondaryMuscles: secondary,
  sets: sets,
);

Workout at(String id, DateTime start, List<WorkoutExercise> exercises) =>
    workout(id, exercises, startedAt: start, finishedAt: start);

void main() {
  CalendarDate d(int y, int m, int day) => CalendarDate(y, m, day);
  final monday = d(2026, 11, 9);

  /// The one week starting on [first] of [workouts].
  WeekVolume week(
    List<Workout> workouts, {
    CalendarDate? first,
    Map<String, ExerciseMuscles> muscles = const {},
  }) => volumeWeeks(
    workouts,
    first: first ?? monday,
    count: 1,
    muscles: muscles,
  ).single;

  group('VolumeZone', () {
    test('holds both ends of the 10-20 band inside it', () {
      expect(VolumeZone.of(0), VolumeZone.below);
      expect(VolumeZone.of(9.5), VolumeZone.below);
      expect(VolumeZone.of(10), VolumeZone.within);
      expect(VolumeZone.of(20), VolumeZone.within);
      expect(VolumeZone.of(20.5), VolumeZone.above);
    });
  });

  group('summary', () {
    // Pecs 12 sets (within), quads 3 (below), lats 21 (above), glutes 1.5
    // as secondary (below).
    final volume = week([
      at('w1', DateTime(2026, 11, 10, 18), [
        worked('bench', List.filled(12, lift(60, 8))),
        worked(
          'squat',
          List.filled(3, lift(100, 5)),
          main: const [Muscle.quads],
          secondary: const [Muscle.glute],
        ),
        worked('row', List.filled(21, lift(50, 10)), main: const [Muscle.lat]),
      ]),
    ]);

    test('muscles by sets, most first, ties in vocabulary order', () {
      expect(volume.musclesBySets.take(5), [
        Muscle.lat,
        Muscle.pec,
        Muscle.quads,
        Muscle.glute,
        // Untrained, in vocabulary order.
        Muscle.trap,
      ]);
      expect(volume.musclesBySets, hasLength(Muscle.values.length));
    });

    test('counts trained muscles per zone, untrained ones in none', () {
      expect(volume.zoneCounts, {
        VolumeZone.below: 2,
        VolumeZone.within: 1,
        VolumeZone.above: 1,
      });
      expect(week(const []).zoneCounts, {
        VolumeZone.below: 0,
        VolumeZone.within: 0,
        VolumeZone.above: 0,
      });
    });
  });

  group('counting', () {
    test('a set counts 1 for main and 0.5 for secondary muscles', () {
      final volume = week([
        at('w1', DateTime(2026, 11, 10, 18), [
          worked(
            'bench',
            [lift(60, 8), lift(60, 8), lift(60, 8)],
            main: [Muscle.pec],
            secondary: [Muscle.triceps, Muscle.frontDelt],
          ),
          worked('dip', [lift(0, 10)], main: [Muscle.triceps]),
        ]),
      ]);
      expect(volume.sets, {
        Muscle.pec: 3.0,
        Muscle.triceps: 2.5,
        Muscle.frontDelt: 1.5,
      });
      expect(volume.setsOf(Muscle.lat), 0);
    });

    test('warm-ups and sets not done do not count; a drop set is one', () {
      final volume = week([
        at('w1', DateTime(2026, 11, 10, 18), [
          worked('bench', [
            lift(20, 10, type: SetType.warmup),
            lift(40, 5, type: SetType.warmup),
            lift(60, 8),
            lift(60, 8, done: false),
            lift(
              60,
              8,
              type: SetType.drop,
              drops: const [Drop(weightKg: 40, reps: 6)],
            ),
          ]),
        ]),
      ]);
      expect(volume.sets, {Muscle.pec: 2.0});
    });

    test('an exercise of only warm-ups leaves no entry', () {
      final volume = week([
        at('w1', DateTime(2026, 11, 10, 18), [
          worked('bench', [lift(20, 10, type: SetType.warmup)]),
        ]),
      ]);
      expect(volume.entries, isEmpty);
      expect(volume.sets, isEmpty);
    });

    test('the library\'s muscles count; the stored ones only for an '
        'exercise no longer there', () {
      final volume = week(
        [
          at('w1', DateTime(2026, 11, 10, 18), [
            worked('fixed', [lift(50, 5)], main: [Muscle.pec]),
            worked('retired', [lift(50, 5)], main: [Muscle.lat]),
          ]),
        ],
        muscles: {
          'fixed': (main: [Muscle.quads], secondary: [Muscle.glute]),
        },
      );
      expect(volume.sets, {
        Muscle.quads: 1.0,
        Muscle.glute: 0.5,
        Muscle.lat: 1.0,
      });
    });

    test('an exercise without muscles counts nothing', () {
      final volume = week([
        at('w1', DateTime(2026, 11, 10, 18), [
          worked('unknown', [lift(50, 5)], main: const []),
        ]),
      ]);
      expect(volume.sets, isEmpty);
      expect(volume.contributionsTo(Muscle.pec), isEmpty);
    });

    test('tells which exercises of which workouts gave a muscle sets', () {
      final volume = week([
        at('late', DateTime(2026, 11, 12, 18), [
          worked('fly', [lift(10, 12)]),
        ]),
        at('early', DateTime(2026, 11, 10, 18), [
          worked('bench', [lift(60, 8), lift(60, 8)]),
          worked('row', [lift(60, 8)], main: [Muscle.lat]),
          worked(
            'pushdown',
            [lift(20, 12)],
            main: [Muscle.triceps],
            secondary: [Muscle.pec],
          ),
        ]),
      ]);
      expect(
        [
          for (final (:entry, :sets) in volume.contributionsTo(Muscle.pec))
            (entry.workoutId, entry.exerciseId, entry.exerciseName, sets),
        ],
        [
          ('early', 'bench', 'Stored bench', 2.0),
          ('early', 'pushdown', 'Stored pushdown', 0.5),
          ('late', 'fly', 'Stored fly', 1.0),
        ],
      );
    });
  });

  group('weeks', () {
    final pec = [lift(60, 8)];

    test('run from local midnight of their first day', () {
      final weeks = volumeWeeks(
        [
          at('sunBefore', DateTime(2026, 11, 8, 23, 59), [worked('a', pec)]),
          at('monday', DateTime(2026, 11, 9), [worked('b', pec)]),
          at('sunday', DateTime(2026, 11, 15, 23, 59), [worked('c', pec)]),
          at('next', DateTime(2026, 11, 16), [worked('d', pec)]),
        ],
        first: monday,
        count: 1,
        muscles: const {},
      );
      expect(
        [for (final e in weeks.single.entries) e.workoutId],
        ['monday', 'sunday'],
      );
    });

    test('start on the locale\'s first weekday', () {
      final workouts = [
        at('sat', DateTime(2026, 11, 14, 10), [worked('a', pec)]),
        at('sun', DateTime(2026, 11, 15, 10), [worked('b', pec)]),
      ];
      List<String> ids(CalendarDate first) => [
        for (final e in volumeWeeks(
          workouts,
          first: first,
          count: 1,
          muscles: const {},
        ).single.entries)
          e.workoutId,
      ];
      // Monday 9, Sunday 15 and Saturday 14 November.
      expect(ids(d(2026, 11, 9)), ['sat', 'sun']);
      expect(ids(d(2026, 11, 15)), ['sun']);
      expect(ids(d(2026, 11, 8)), ['sat']);
      expect(ids(d(2026, 11, 14)), ['sat', 'sun']);
    });

    test('keep their dates across a daylight saving change', () {
      // Europe leaves summer time on Sunday 25 October 2026, the United
      // States on Sunday 1 November; run with TZ set to check either.
      final workouts = [
        at('eu', DateTime(2026, 10, 25, 23, 30), [worked('a', pec)]),
        at('euNext', DateTime(2026, 10, 26, 0, 30), [worked('b', pec)]),
        at('us', DateTime(2026, 11, 1, 0, 30), [worked('c', pec)]),
        at('usBefore', DateTime(2026, 10, 31, 23, 30), [worked('d', pec)]),
      ];
      List<List<String>> ids(CalendarDate first) => [
        for (final week in volumeWeeks(
          workouts,
          first: first,
          count: 3,
          muscles: const {},
        ))
          [for (final e in week.entries) e.workoutId],
      ];
      expect(ids(d(2026, 10, 19)), [
        ['eu'],
        ['euNext', 'usBefore', 'us'],
        <String>[],
      ]);
      expect(ids(d(2026, 10, 18)), [
        <String>[],
        ['eu', 'euNext', 'usBefore'],
        ['us'],
      ]);
    });

    test('come oldest first with empty ones, as a trend per muscle', () {
      final weeks = volumeWeeks(
        [
          at('w3', DateTime(2026, 11, 10), [
            worked('a', [lift(60, 8), lift(60, 8)]),
          ]),
          at('w1', DateTime(2026, 10, 27), [worked('b', pec)]),
          at('old', DateTime(2026, 10, 25), [worked('c', pec)]),
        ],
        first: d(2026, 10, 26),
        count: 3,
        muscles: const {},
      );
      expect(
        [for (final w in weeks) w.start],
        [d(2026, 10, 26), d(2026, 11, 2), d(2026, 11, 9)],
      );
      expect([for (final w in weeks) w.setsOf(Muscle.pec)], [1.0, 0.0, 2.0]);
      expect(weeks.last.end, d(2026, 11, 15));
    });
  });

  group('WatchWeeklyVolume', () {
    test('reads the weeks ending with the given one', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () async {},
      );
      for (final w in [
        at('tooOld', DateTime(2026, 8, 16, 12), [
          worked('a', [lift(1, 1)]),
        ]),
        at('first', DateTime(2026, 8, 17, 12), [
          worked('b', [lift(1, 1)]),
        ]),
        at('last', DateTime(2026, 11, 8, 12), [
          worked('c', [lift(1, 1)]),
        ]),
        at('tooNew', DateTime(2026, 11, 9, 12), [
          worked('d', [lift(1, 1)]),
        ]),
      ]) {
        await repository.saveWorkout('u1', w, const {});
      }
      final watch = WatchWeeklyVolume(WatchWorkoutsBetween(repository));

      final weeks = await watch((
        uid: 'u1',
        lastWeek: d(2026, 11, 2),
        weeks: trendWeeks,
        muscles: const {},
      )).first;

      expect(weeks, hasLength(trendWeeks));
      expect(weeks.first.start, d(2026, 8, 17));
      expect(weeks.last.start, d(2026, 11, 2));
      expect(weeks.first.entries.single.workoutId, 'first');
      expect(weeks.last.entries.single.workoutId, 'last');
      expect(weeks.fold(0, (n, w) => n + w.entries.length), 2);
    });
  });
}
