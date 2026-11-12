import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  final first = DateTime(2026, 1, 1, 18);
  const pageSize = FirestoreWorkoutRepository.historyPageSize;

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

  group('history pages', () {
    test('newest first, a page at a time, joined by their ends', () async {
      await store([for (var day = 0; day < pageSize + 5; day++) day]);

      final page1 = await repository.watchHistory('u1').first;
      expect(page1.workouts, hasLength(pageSize));
      expect(page1.workouts.first.id, 'w${pageSize + 4}');
      expect(page1.more, isTrue);

      final page2 = await repository.watchHistory('u1', after: page1.end).first;
      expect(ids(page2.workouts), ['w4', 'w3', 'w2', 'w1', 'w0']);
      expect(page2.more, isFalse);
    });

    test('a page with an end grows instead of dropping one', () async {
      await store([for (var day = 0; day < pageSize + 1; day++) day]);
      final page1 = await repository.watchHistory('u1').first;
      final end = page1.end;

      // A newer workout pushes the open page's last one out...
      await store([100]);
      final open = await repository.watchHistory('u1').first;
      expect(open.workouts.last.id, isNot(page1.workouts.last.id));

      // ...while the page with an end keeps it, so the next page starting
      // after it neither skips nor repeats one.
      final bounded = await repository.watchHistory('u1', through: end).first;
      expect(bounded.workouts, hasLength(pageSize + 1));
      expect(bounded.workouts.first.id, 'w100');
      expect(bounded.workouts.last.id, page1.workouts.last.id);
      final next = await repository.watchHistory('u1', after: end).first;
      expect(ids(next.workouts), ['w0']);
    });

    test('a page follows edits and deletions', () async {
      await store([0, 1]);
      final pages = repository.watchHistory('u1');
      final seen = <List<String>>[];
      final subscription = pages.listen((page) => seen.add(ids(page.workouts)));
      await pumpEventQueue();
      await repository.deleteWorkout('u1', 'w1', const {});
      await pumpEventQueue();
      expect(seen.first, ['w1', 'w0']);
      expect(seen.last, ['w0']);
      await subscription.cancel();
    });

    test('nothing stored is an empty page without an end', () async {
      final page = await repository.watchHistory('u1').first;
      expect(page.workouts, isEmpty);
      expect(page.end, isNull);
      expect(page.more, isFalse);
    });
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
}
