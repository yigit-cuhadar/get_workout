import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/completed_days.dart';
import 'package:get_workout/features/workout/data/file_active_workout_store.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/data/workout_completed_days.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  final start = DateTime(2026, 11, 11, 18);
  final end = DateTime(2026, 11, 11, 19, 5);
  final full = Workout(
    id: 'w1',
    startedAt: start,
    finishedAt: end,
    programId: 'p1',
    dayIndex: 1,
    name: 'Legs',
    note: 'Felt strong',
    exercises: [
      WorkoutExercise(
        exerciseId: 'squat',
        name: 'Back Squat',
        loggingType: LoggingType.weightReps,
        mainMuscles: const [Muscle.quads, Muscle.glute],
        secondaryMuscles: const [Muscle.erector],
        group: 'A',
        note: 'Belt',
        sets: [
          lift(60, 5, type: SetType.warmup),
          const WorkoutSet(
            type: SetType.drop,
            weightKg: 100,
            reps: 6,
            toFailure: true,
            rir: 0,
            note: 'Grind',
            drops: [Drop(weightKg: 80, reps: 4)],
            done: true,
          ),
        ],
      ),
      exercise(
        'plank',
        [const WorkoutSet(durationS: 60, done: true)],
        type: LoggingType.duration,
        group: 'A',
      ),
    ],
  );

  group('FirestoreWorkoutRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreWorkoutRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreWorkoutRepository(firestore);
    });

    DocumentReference<Map<String, dynamic>> stats(String id) =>
        firestore.doc('users/u1/exerciseStats/$id');

    test('stores the workout and stats in one go', () async {
      final squat = applyWorkout(null, full, 'squat')!;
      final result = await repository.saveWorkout('u1', full, {'squat': squat});
      expect(result.isOk, isTrue);
      await pumpEventQueue();

      final doc = await firestore.doc('users/u1/workouts/w1').get();
      expect(doc.data()!['exerciseIds'], ['squat', 'plank']);
      expect(doc.data()!['startedAt'], Timestamp.fromDate(start));
      final sets = (doc.data()!['exercises'] as List).first['sets'] as List;
      expect(sets.first, {
        'type': 'warmup',
        'weightKg': 60.0,
        'reps': 5,
        'toFailure': false,
        'done': true,
      });
      expect(
        FirestoreWorkoutRepository.workoutFromMap('w1', doc.data()!),
        full,
      );
      expect(await repository.watchStats('u1', 'squat').first, squat);
      expect(await repository.watchStats('u1', 'plank').first, isNull);
    });

    test('stats round trip through their map', () {
      final stats = applyWorkout(null, full, 'squat')!;
      expect(
        FirestoreWorkoutRepository.statsFromMap(
          FirestoreWorkoutRepository.statsToMap(stats),
        ),
        stats,
      );
    });

    test('unreadable parts of stats are left out', () {
      final stats = FirestoreWorkoutRepository.statsFromMap({
        'records': {
          'heaviestWeight': {'value': 'heavy'},
          'mostReps': {
            'value': 12,
            'date': Timestamp.fromDate(start),
            'workoutId': 'w1',
          },
          'unknown': {'value': 1},
        },
        'last': 'yesterday',
        'history': [
          {'date': Timestamp.fromDate(end), 'workoutId': 'w2'},
          'point',
          {'date': Timestamp.fromDate(start), 'workoutId': 'w1', 'volumeKg': 5},
        ],
      })!;
      expect(stats.records, {
        RecordKind.mostReps: StatRecord(
          value: 12,
          date: start,
          workoutId: 'w1',
        ),
      });
      expect(stats.last, isNull);
      expect(stats.history.map((p) => p.workoutId), ['w1', 'w2']);
    });

    test('a workout without its times or name is unreadable', () {
      expect(
        FirestoreWorkoutRepository.workoutFromMap('w1', {'name': 'x'}),
        isNull,
      );
    });

    test('getStats returns known and missing stats', () async {
      await stats('squat').set(
        FirestoreWorkoutRepository.statsToMap(
          applyWorkout(null, full, 'squat')!,
        ),
      );
      final result = await repository.getStats('u1', ['squat', 'plank']);
      expect(result.valueOrNull, {
        'squat': applyWorkout(null, full, 'squat'),
        'plank': null,
      });
    });

    test('new workout ids differ', () {
      expect(
        repository.newWorkoutId('u1'),
        isNot(repository.newWorkoutId('u1')),
      );
    });
  });

  group('WorkoutCompletedDays', () {
    test('reports the program days of workouts in the range', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreWorkoutRepository(firestore);
      Future<void> store(String id, DateTime at, {String? program, int? day}) =>
          repository.saveWorkout(
            'u1',
            workout(
              id,
              [
                exercise('squat', [lift(100, 5)]),
              ],
              startedAt: at,
              finishedAt: at,
              programId: program,
              dayIndex: day,
            ),
            const {},
          );
      await store('w1', DateTime(2026, 11, 9, 7), program: 'p1', day: 0);
      await store('w2', DateTime(2026, 11, 11, 23, 30), program: 'p1', day: 1);
      await store('w3', DateTime(2026, 11, 10), program: 'p2', day: 0);
      await store('w4', DateTime(2026, 11, 10));
      await store('w5', DateTime(2026, 11, 16), program: 'p1', day: 0);
      await pumpEventQueue();

      final days = await WorkoutCompletedDays(firestore)
          .watch(
            'u1',
            'p1',
            from: CalendarDate(2026, 11, 9),
            to: CalendarDate(2026, 11, 15),
          )
          .first;
      expect(days, [
        CompletedDay(date: CalendarDate(2026, 11, 9), dayIndex: 0),
        CompletedDay(date: CalendarDate(2026, 11, 11), dayIndex: 1),
      ]);
    });
  });

  group('FileActiveWorkoutStore', () {
    late Directory directory;
    late FileActiveWorkoutStore store;
    final draft = full.copyWith(
      exercises: [
        full.exercises.first.copyWith(
          goal: () => item('squat', sets: 2, targetKg: 100),
          sets: [...full.exercises.first.sets, const WorkoutSet()],
        ),
        full.exercises.last,
      ],
    );
    final inProgress = Workout(
      id: draft.id,
      startedAt: draft.startedAt,
      programId: draft.programId,
      dayIndex: draft.dayIndex,
      name: draft.name,
      note: draft.note,
      exercises: draft.exercises,
    );

    setUp(() {
      directory = Directory.systemTemp.createTempSync('workout_store');
      store = FileActiveWorkoutStore(() async => directory);
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('keeps the workout in progress with its goals', () async {
      expect((await store.save('u1', inProgress)).isOk, isTrue);
      expect((await store.load('u1')).valueOrNull, inProgress);
    });

    test('each user only ever gets their own', () async {
      await store.save('u1', inProgress);
      expect((await store.load('u2')).valueOrNull, isNull);
      // A file renamed to another user's still belongs to its writer.
      File('${directory.path}/active_workout_u1.json')
          .renameSync('${directory.path}/active_workout_u2.json');
      expect((await store.load('u2')).valueOrNull, isNull);
    });

    test('the latest of quick saves wins, then clear removes it', () async {
      final renamed = Workout(
        id: inProgress.id,
        startedAt: inProgress.startedAt,
        name: 'Renamed',
      );
      final saves = [store.save('u1', inProgress), store.save('u1', renamed)];
      await Future.wait(saves);
      expect((await store.load('u1')).valueOrNull, renamed);
      await store.clear('u1');
      expect((await store.load('u1')).valueOrNull, isNull);
      expect(directory.listSync(), isEmpty);
    });

    test('a damaged file reads as none', () async {
      File('${directory.path}/active_workout_u1.json')
          .writeAsStringSync('{"uid": "u1", "id"');
      expect((await store.load('u1')).valueOrNull, isNull);
    });
  });
}
