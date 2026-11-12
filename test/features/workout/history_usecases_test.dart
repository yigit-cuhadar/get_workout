import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  final monday = DateTime(2026, 11, 9, 18);
  final wednesday = DateTime(2026, 11, 11, 18);
  final friday = DateTime(2026, 11, 13, 18);
  final hour = const Duration(hours: 1);
  final later = DateTime(2026, 12, 1);

  Workout at(String id, DateTime start, List<WorkoutExercise> exercises) =>
      workout(id, exercises, startedAt: start, finishedAt: start.add(hour));

  final w1 = at('w1', monday, [
    exercise('squat', [lift(100, 5)]),
    exercise('bench', [lift(60, 8)]),
  ]);
  final w2 = at('w2', wednesday, [
    exercise('squat', [lift(110, 5)]),
  ]);
  final w3 = at('w3', friday, [
    exercise('squat', [lift(90, 10)]),
  ]);

  group('SaveWorkoutChange on the stored workouts', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreWorkoutRepository repository;
    late SaveWorkoutChange save;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () async {},
      );
      save = SaveWorkoutChange(repository, clock: () => later);
      for (final w in [w1, w2, w3]) {
        await repository.saveWorkout('u1', w, const {});
      }
      for (final id in ['squat', 'bench']) {
        await repository.saveStats('u1', id, rebuildStats(id, [w1, w2, w3]));
      }
      await pumpEventQueue();
    });

    Future<ExerciseStats?> stats(String id) =>
        repository.watchStats('u1', id).first;

    Future<Set<String>> change({Workout? before, Workout? after}) async {
      final result = await save((uid: 'u1', before: before, after: after));
      await pumpEventQueue();
      return result.valueOrNull!;
    }

    test('records move to the workout that now holds them', () async {
      final lighter = w2.copyWith(
        exercises: [
          exercise('squat', [lift(80, 5)]),
        ],
      );
      // A rebuild from the server follows every change.
      expect(await change(before: w2, after: lighter), {'squat'});

      final squat = (await stats('squat'))!;
      expect(squat, rebuildStats('squat', [w1, lighter, w3]));
      expect(squat.records[RecordKind.heaviestWeight]!.workoutId, 'w1');
      expect(squat.records[RecordKind.bestE1rm]!.workoutId, 'w3');
      expect(squat.history.map((p) => (p.workoutId, p.volumeKg)), [
        ('w1', 500),
        ('w2', 400),
        ('w3', 900),
      ]);
      final stored = await repository.watchWorkout('u1', 'w2').first;
      expect(stored!.workout.exercises.single.sets, [lift(80, 5)]);
    });

    test('moving a workout\'s start keeps last time the true latest', () async {
      final earlier = w3.copyWith(
        startedAt: monday.subtract(const Duration(days: 1)),
        finishedAt: monday.subtract(const Duration(days: 1)).add(hour),
      );
      await change(before: w3, after: earlier);

      final squat = (await stats('squat'))!;
      expect(squat.last!.workoutId, 'w2');
      expect(squat.last!.sets, [lift(110, 5)]);
      expect(squat.history.map((p) => p.workoutId), ['w3', 'w1', 'w2']);
    });

    test('an exercise taken out loses its point; one added gains it', () async {
      final swapped = w1.copyWith(
        exercises: [
          exercise('squat', [lift(100, 5)]),
          exercise('row', [lift(70, 8)]),
        ],
      );
      await change(before: w1, after: swapped);

      // Bench was only in w1.
      expect(await stats('bench'), isNull);
      expect(
        (await firestore.doc('users/u1/exerciseStats/bench').get()).exists,
        isFalse,
      );
      final row = (await stats('row'))!;
      expect(row.history.single.workoutId, 'w1');
      expect(row.last!.workoutId, 'w1');
      expect(await stats('squat'), rebuildStats('squat', [w1, w2, w3]));
    });

    test('deleting rebuilds without the workout', () async {
      await change(before: w3);
      final squat = (await stats('squat'))!;
      expect(squat.last!.workoutId, 'w2');
      expect(squat.history.map((p) => p.workoutId), ['w1', 'w2']);
      expect(
        squat.records.values.map((r) => r.workoutId),
        isNot(contains('w3')),
      );
      expect(await repository.watchWorkout('u1', 'w3').first, isNull);

      // The only workout with bench: its stats go.
      await change(before: w1);
      expect(await stats('bench'), isNull);
      expect((await stats('squat'))!.history.single.workoutId, 'w2');
    });

    test('a past workout lands in order and takes its records', () async {
      final past = at('w0', monday.subtract(const Duration(days: 7)), [
        exercise('squat', [lift(150, 1), lift(160, 1, done: false)]),
      ]);
      await change(after: past);

      final squat = (await stats('squat'))!;
      expect(squat.records[RecordKind.heaviestWeight]!.workoutId, 'w0');
      expect(squat.records[RecordKind.heaviestWeight]!.value, 150);
      expect(squat.last!.workoutId, 'w3');
      expect(squat.history.map((p) => p.workoutId), ['w0', 'w1', 'w2', 'w3']);
      // Unticked sets are left out.
      final stored = await repository.watchWorkout('u1', 'w0').first;
      expect(stored!.workout.exercises.single.sets, [lift(150, 1)]);
    });

    test('the active program is never touched', () async {
      final fromProgram = workout(
        'w4',
        [
          exercise('squat', [lift(100, 5)]),
        ],
        startedAt: friday.add(const Duration(days: 1)),
        finishedAt: friday.add(const Duration(days: 1)).add(hour),
        programId: 'p1',
        dayIndex: 0,
      );
      await change(after: fromProgram);
      await change(before: w2);
      expect((await firestore.doc('users/u1').get()).exists, isFalse);
    });

    test(
      'a workout without a done set or with an invalid one is refused',
      () async {
        final nothingDone = w2.copyWith(
          exercises: [
            exercise('squat', [lift(110, 5, done: false)]),
          ],
        );
        final invalid = w2.copyWith(
          exercises: [
            exercise('squat', [lift(110, 0)]),
          ],
        );
        final unnamed = w2.copyWith(name: '');
        for (final after in [nothingDone, invalid, unnamed]) {
          final result = await save((uid: 'u1', before: w2, after: after));
          expect(result.failureOrNull, isA<ValidationFailure>());
        }
        final stored = await repository.watchWorkout('u1', 'w2').first;
        expect(stored!.workout, w2);
      },
    );

    test('times in the future or over a day are refused', () async {
      Future<String?> refusal(DateTime start, Duration length) async {
        final result = await save((
          uid: 'u1',
          before: null,
          after: at(
            'w5',
            start,
            w2.exercises,
          ).copyWith(finishedAt: start.add(length)),
        ));
        return (result.failureOrNull as ValidationFailure?)?.message;
      }

      expect(await refusal(later.add(hour), hour), 'startInFuture');
      expect(await refusal(later.subtract(hour), hour * 2), 'endInFuture');
      expect(await refusal(monday, hour * 25), 'badDuration');
      expect(await refusal(monday, hour * 24), isNull);
      expect(await refusal(later.subtract(hour), hour), isNull);
    });
  });

  group('SaveWorkoutChange reading what the device knows', () {
    late MockWorkoutRepository repository;

    setUpAll(() {
      registerFallbackValue(w1);
      registerFallbackValue(<String, ExerciseStats?>{});
    });

    setUp(() {
      repository = MockWorkoutRepository();
      when(() => repository.updateWorkout(any(), any(), any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test(
      'from the cache no stats are written; all are rebuilt later',
      () async {
        when(() => repository.workoutsDoing('u1', ['squat', 'bench']))
            .thenAnswer(
              (_) async => Ok((
                workouts: {
                  'squat': (workouts: [w1], complete: true),
                  'bench': (workouts: [w1], complete: true),
                },
                current: false,
              )),
            );
        final edited = w1.copyWith(
          exercises: [
            exercise('squat', [lift(105, 5)]),
            exercise('bench', [lift(60, 8)]),
          ],
        );
        final stale = await SaveWorkoutChange(repository, clock: () => later)((
          uid: 'u1',
          before: w1,
          after: edited,
        ));
        expect(stale.valueOrNull, {'squat', 'bench'});
        final saved =
            verify(() => repository.updateWorkout('u1', edited, captureAny()))
                    .captured
                    .single
                as Map<String, ExerciseStats?>;
        // The cache may lack workouts: a rebuild from it could lose records.
        expect(saved, isEmpty);
      },
    );

    test('an exercise with too many workouts keeps its stats', () async {
      when(() => repository.workoutsDoing('u1', ['squat'])).thenAnswer(
        (_) async => Ok((
          workouts: {
            'squat': (workouts: [w2], complete: false),
          },
          current: true,
        )),
      );
      final result = await SaveWorkoutChange(repository, clock: () => later)((
        uid: 'u1',
        before: w2,
        after: w2,
      ));
      expect(result.valueOrNull, {'squat'});
      final saved =
          verify(() => repository.updateWorkout('u1', w2, captureAny()))
                  .captured
                  .single
              as Map<String, ExerciseStats?>;
      expect(saved, isEmpty);
    });

    test('a read that fails stores nothing', () async {
      when(() => repository.workoutsDoing(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final result = await SaveWorkoutChange(repository, clock: () => later)((
        uid: 'u1',
        before: w2,
        after: null,
      ));
      expect(result.failureOrNull, isA<NetworkFailure>());
      verifyNever(() => repository.deleteWorkout(any(), any(), any()));
    });
  });
}
