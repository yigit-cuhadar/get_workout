import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/completed_days.dart';
import 'package:get_workout/features/workout/data/file_local_workout_store.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/data/workout_completed_days.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';

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
      repository = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () async {},
      );
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
        'squat': (stats: applyWorkout(null, full, 'squat'), current: true),
        'plank': (stats: null, current: true),
      });
    });

    test('isStored says whether the server has the workout', () async {
      await repository.saveWorkout('u1', full, const {});
      await pumpEventQueue();
      expect((await repository.isStored('u1', 'w1')).valueOrNull, isTrue);
      expect((await repository.isStored('u1', 'w9')).valueOrNull, isFalse);
    });

    test(
      'an acknowledged workout deleted since still counts as stored',
      () async {
        await repository.saveWorkout('u1', full, const {});
        await pumpEventQueue();
        // Deleted on another device before the confirmation runs.
        await firestore.doc('users/u1/workouts/w1').delete();
        expect((await repository.isStored('u1', 'w1')).valueOrNull, isTrue);
      },
    );

    test('a refused workout is not stored', () async {
      final refusing = FakeFirebaseFirestore(
        securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read: if true;
      allow write: if false;
    }
  }
}
''',
      );
      final repository = FirestoreWorkoutRepository(
        refusing,
        waitForPendingWrites: () async {},
      );
      await repository.saveWorkout('u1', full, const {});
      expect((await repository.isStored('u1', 'w1')).valueOrNull, isFalse);
    });

    test('after a restart the server\'s copy decides', () async {
      await repository.saveWorkout('u1', full, const {});
      await pumpEventQueue();
      final restarted = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () async {},
      );
      expect((await restarted.isStored('u1', 'w1')).valueOrNull, isTrue);
      await firestore.doc('users/u1/workouts/w1').delete();
      expect((await restarted.isStored('u1', 'w1')).valueOrNull, isFalse);
    });

    test('a rebuild reads only once pending writes are answered', () async {
      final pending = Completer<void>();
      final repository = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () => pending.future,
      );
      var done = false;
      final read = repository
          .workoutsWith('u1', 'squat')
          .whenComplete(() => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      // The edit lands before the read.
      await firestore
          .doc('users/u1/workouts/w1')
          .set(FirestoreWorkoutRepository.workoutToMap(full));
      pending.complete();
      expect((await read).valueOrNull!.workouts, [full]);
    });

    test('rebuild reads the exercise\'s workouts and replaces stats', () async {
      await repository.saveWorkout('u1', full, const {});
      await repository.saveWorkout(
        'u1',
        workout('w2', [
          exercise('bench', [lift(80, 5)]),
        ], finishedAt: end),
        const {},
      );
      await pumpEventQueue();
      final read = (await repository.workoutsWith('u1', 'squat')).valueOrNull!;
      expect(read.complete, isTrue);
      expect(read.workouts, [full]);

      final rebuilt = rebuildStats('squat', read.workouts);
      await repository.saveStats('u1', 'squat', rebuilt);
      await pumpEventQueue();
      expect(await repository.watchStats('u1', 'squat').first, rebuilt);
      await repository.saveStats('u1', 'squat', null);
      await pumpEventQueue();
      expect((await stats('squat').get()).exists, isFalse);
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

      final days = await WorkoutCompletedDays(repository)
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

  group('FileLocalWorkoutStore', () {
    late Directory directory;
    late FileLocalWorkoutStore store;
    final inProgress = Workout(
      id: 'w2',
      startedAt: start,
      programId: 'p1',
      dayIndex: 1,
      name: 'Legs',
      note: 'Felt strong',
      exercises: [
        full.exercises.first.copyWith(
          goal: () => item('squat', sets: 2, targetKg: 100),
          sets: [...full.exercises.first.sets, const WorkoutSet()],
        ),
        full.exercises.last,
      ],
    );
    final kept = LocalWorkouts(
      draft: inProgress,
      finished: [full],
      staleStats: const {'squat'},
    );

    File file(String name) => File('${directory.path}/$name');

    setUp(() {
      directory = Directory.systemTemp.createTempSync('workout_store');
      store = FileLocalWorkoutStore(
        () async => directory,
        clock: () => DateTime.fromMillisecondsSinceEpoch(42),
      );
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('keeps drafts with goals, finished workouts and stale ids', () async {
      expect((await store.save('u1', kept)).isOk, isTrue);
      expect((await store.load('u1')).valueOrNull, kept);
    });

    test('nothing kept reads as empty', () async {
      expect((await store.load('u1')).valueOrNull, const LocalWorkouts());
    });

    test('each user only ever gets their own', () async {
      await store.save('u1', kept);
      expect((await store.load('u2')).valueOrNull, const LocalWorkouts());
      // A file renamed to another user's still belongs to its writer: it is
      // set aside, not shown.
      file('workouts_u1.json').renameSync('${directory.path}/workouts_u2.json');
      expect((await store.load('u2')).failureOrNull, isA<UnknownFailure>());
      expect(file('workouts_u2.json.unreadable-42').existsSync(), isTrue);
    });

    test('the latest of quick saves wins', () async {
      final later = kept.copyWith(draft: () => null);
      await Future.wait([store.save('u1', kept), store.save('u1', later)]);
      expect((await store.load('u1')).valueOrNull, later);
      expect(directory.listSync().map((e) => e.uri.pathSegments.last), [
        'workouts_u1.json',
      ]);
    });

    test('a damaged file is set aside, never overwritten', () async {
      file('workouts_u1.json').writeAsStringSync('{"uid": "u1", "id"');
      expect((await store.load('u1')).failureOrNull, isA<UnknownFailure>());
      expect(
        file('workouts_u1.json.unreadable-42').readAsStringSync(),
        '{"uid": "u1", "id"',
      );
      await store.save('u1', const LocalWorkouts());
      expect((await store.load('u1')).valueOrNull, const LocalWorkouts());
    });

    test('an unknown version is set aside too', () async {
      file('workouts_u1.json').writeAsStringSync(
        '{"version": 99, "uid": "u1", "finished": [], "staleStats": []}',
      );
      expect((await store.load('u1')).failureOrNull, isA<UnknownFailure>());
      expect(file('workouts_u1.json.unreadable-42').existsSync(), isTrue);
    });

    test('a read that fails otherwise is set aside as well', () async {
      final unreadable = file('workouts_u1.json')..writeAsStringSync('{}');
      // Not a format problem: the file cannot be opened at all.
      Process.runSync('chmod', ['000', unreadable.path]);
      if (_isRoot) {
        markTestSkipped('root reads files without permission');
        return;
      }
      final result = await store.load('u1');
      expect(result.failureOrNull, isA<UnknownFailure>());
      expect(file('workouts_u1.json.unreadable-42').existsSync(), isTrue);
      expect((await store.save('u1', kept)).isOk, isTrue);
      expect((await store.load('u1')).valueOrNull, kept);
    });
  });
}

/// Root ignores file permissions, so a permission test cannot fail a read.
final _isRoot = (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
