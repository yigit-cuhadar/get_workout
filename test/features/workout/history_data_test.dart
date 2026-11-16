import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  final first = DateTime(2026, 1, 1, 18);

  late FakeFirebaseFirestore firestore;
  late FirestoreWorkoutRepository repository;

  /// Workout `w<day>`, started [day] days after [first].
  Workout onDay(int day) => workout(
    'w$day',
    [
      exercise('squat', [lift(100, 5)]),
    ],
    startedAt: first.add(Duration(days: day)),
    finishedAt: first.add(Duration(days: day, hours: 1)),
  );

  Future<void> store(Iterable<int> days) async {
    for (final day in days) {
      await repository.saveWorkout('u1', onDay(day), const {});
    }
    await pumpEventQueue();
  }

  List<String> ids(List<Workout> workouts) => [for (final w in workouts) w.id];

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreWorkoutRepository(
      firestore,
      waitForPendingWrites: () async {},
    );
  });

  group('a stored workout', () {
    test('is watched until it is deleted', () async {
      await store([0]);
      final stored = await repository.watchWorkout('u1', 'w0').first;
      expect(stored!.workout, onDay(0));
      expect(stored.pending, isFalse);

      await repository.deleteWorkout('u1', 'w0', const {});
      await pumpEventQueue();
      expect(await repository.watchWorkout('u1', 'w0').first, isNull);
    });

    test(
      'an update replaces it and its stats; null stats are removed',
      () async {
        await store([0]);
        await repository.saveStats(
          'u1',
          'squat',
          rebuildStats('squat', [onDay(0)]),
        );
        final edited = onDay(0).copyWith(
          name: 'Renamed',
          exercises: [
            exercise('row', [lift(70, 8)]),
          ],
        );
        final rowStats = rebuildStats('row', [edited])!;
        final result = await repository.updateWorkout('u1', edited, {
          'squat': null,
          'row': rowStats,
        });
        expect(result.isOk, isTrue);
        await pumpEventQueue();

        final stored = await repository.watchWorkout('u1', 'w0').first;
        expect(stored!.workout, edited);
        expect(await repository.watchStats('u1', 'squat').first, isNull);
        expect(await repository.watchStats('u1', 'row').first, rowStats);
      },
    );
  });

  group('workouts of several exercises', () {
    test('come from the server when it answers', () async {
      await store([0, 1]);
      await repository.saveWorkout(
        'u1',
        workout('w9', [
          exercise('bench', [lift(60, 8)]),
        ], finishedAt: first),
        const {},
      );
      final read = (await repository.workoutsDoing('u1', [
        'squat',
        'bench',
        'row',
      ])).valueOrNull!;
      expect(read.current, isTrue);
      expect(ids(read.workouts['squat']!.workouts).toSet(), {'w0', 'w1'});
      expect(ids(read.workouts['bench']!.workouts), ['w9']);
      expect(read.workouts['row']!.workouts, isEmpty);
      expect(read.workouts['row']!.complete, isTrue);
    });

    test('come from the cache while writes wait for the server', () async {
      final never = Completer<void>();
      repository = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () => never.future,
      );
      await store([0]);
      final read = (await repository.workoutsDoing('u1', [
        'squat',
      ])).valueOrNull!;
      expect(read.current, isFalse);
      expect(ids(read.workouts['squat']!.workouts), ['w0']);
    });
  });

  group('all stats', () {
    test('every exercise of the user, by id, again on a change', () async {
      final squat = rebuildStats('squat', [onDay(0)])!;
      await repository.saveStats('u1', 'squat', squat);
      await repository.saveStats('u2', 'bench', squat);
      final stats = StreamIterator(repository.watchAllStats('u1'));

      expect(await stats.moveNext(), isTrue);
      expect(stats.current, {'squat': squat});

      await repository.saveStats('u1', 'squat', null);
      expect(await stats.moveNext(), isTrue);
      expect(stats.current, isEmpty);
      await stats.cancel();
    });
  });

  group('workouts between dates', () {
    Workout at(String id, DateTime start) => workout(
      id,
      [
        exercise('squat', [lift(100, 5)]),
      ],
      startedAt: start,
      finishedAt: start.add(const Duration(hours: 1)),
    );

    test('by local start date, both ends included, oldest first', () async {
      for (final w in [
        at('late', DateTime(2026, 11, 30, 23, 59)),
        at('before', DateTime(2026, 10, 31, 23, 59)),
        at('first', DateTime(2026, 11, 1)),
        at('after', DateTime(2026, 12, 1)),
        at('mid', DateTime(2026, 11, 15, 12)),
      ]) {
        await repository.saveWorkout('u1', w, const {});
      }
      await repository.saveWorkout(
        'u2',
        at('other', DateTime(2026, 11, 15)),
        const {},
      );
      await pumpEventQueue();

      final read = await repository
          .watchWorkoutsBetween(
            'u1',
            from: CalendarDate(2026, 11, 1),
            to: CalendarDate(2026, 11, 30),
          )
          .first;
      expect(ids(read), ['first', 'mid', 'late']);
    });

    test('follow changes', () async {
      final emitted = repository
          .watchWorkoutsBetween(
            'u1',
            from: CalendarDate(2026, 11, 1),
            to: CalendarDate(2026, 11, 30),
          )
          .map(ids);
      final expectation = expectLater(
        emitted,
        emitsInOrder([
          <String>[],
          ['w1'],
        ]),
      );
      await repository.saveWorkout(
        'u1',
        at('w1', DateTime(2026, 11, 2, 8)),
        const {},
      );
      await expectation;
    });
  });
}
