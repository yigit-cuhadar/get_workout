import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/data/firestore_exercise_repository.dart';
import 'package:get_workout/features/exercises/data/firestore_exercise_source.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

class MockSource extends Mock implements FirestoreExerciseSource {}

Timestamp at(int day) => Timestamp.fromDate(DateTime.utc(2026, 11, day));

/// A document as the content tooling stores it in Firestore.
Map<String, Object?> document({
  String status = 'live',
  required int popularity,
  required Timestamp updatedAt,
}) => {
  'status': status,
  'loggingType': 'weight_reps',
  'mechanic': 'compound',
  'laterality': 'bilateral',
  'level': 'beginner',
  'force': 'push',
  'movementPattern': 'horizontal_push',
  'position': 'supine',
  'equipment': ['barbell', 'bench'],
  'equipmentAlternatives': [
    {
      'items': ['dumbbell', 'bench'],
    },
  ],
  'mainMuscles': ['pec'],
  'secondaryMuscles': ['triceps'],
  'family': 'bench_press',
  'familyRank': 1,
  'pinnedAlternatives': <String>[],
  'excludedAlternatives': <String>[],
  'defaultRestS': 120,
  'incrementKg': 2.5,
  'popularity': popularity,
  'contentHash': 'hash',
  'l10n': {
    'en': {
      'name': 'Press $popularity',
      'aliases': <String>[],
      'setup': <String>[],
      'execution': <String>[],
      'mistakes': <String>[],
      'cues': <String>[],
    },
  },
  'updatedAt': updatedAt,
};

List<String> ids(List<Exercise> exercises) => [for (final e in exercises) e.id];

void main() {
  group('with Firestore (fake)', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreExerciseRepository repository;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreExerciseRepository(
        FirestoreExerciseSource(firestore),
      );
      final exercises = firestore.collection('exercises');
      await exercises.doc('b').set(document(popularity: 2, updatedAt: at(1)));
      await exercises.doc('a').set(document(popularity: 1, updatedAt: at(2)));
      await exercises
          .doc('draft')
          .set(document(status: 'draft', popularity: 3, updatedAt: at(2)));
      await exercises
          .doc('retired')
          .set(document(status: 'retired', popularity: 4, updatedAt: at(1)));
      await exercises.doc('broken').set({
        ...document(popularity: 5, updatedAt: at(1)),
        'level': 'expert',
      });
    });

    test(
      'the first sync loads the live, well-formed ones by popularity',
      () async {
        final result = await repository.sync();

        expect(result.isOk, isTrue);
        final exercises = await repository.watchExercises().first;
        expect(ids(exercises), ['a', 'b']);
        expect(exercises.first.equipmentAlternatives, [
          [Equipment.dumbbell, Equipment.bench],
        ]);
        expect(exercises.first.incrementKg, 2.5);
        expect(exercises.first.updatedAt?.toUtc(), DateTime.utc(2026, 11, 2));
      },
    );

    test(
      'a later sync picks up retired, published and new documents',
      () async {
        await repository.sync();
        final exercises = firestore.collection('exercises');
        await exercises.doc('a').update({
          'status': 'retired',
          'updatedAt': at(3),
        });
        await exercises.doc('draft').update({
          'status': 'live',
          'updatedAt': at(3),
        });
        await exercises.doc('c').set(document(popularity: 0, updatedAt: at(4)));

        final emitted = <List<String>>[];
        final subscription = repository.watchExercises().listen(
          (list) => emitted.add(ids(list)),
        );
        final result = await repository.sync();
        await pumpEventQueue();
        await subscription.cancel();

        expect(result.isOk, isTrue);
        expect(emitted, [
          ['a', 'b'],
          ['c', 'b', 'draft'],
        ]);
      },
    );

    test('a sync without changes emits nothing new', () async {
      await repository.sync();
      final emitted = <List<Exercise>>[];
      final subscription = repository.watchExercises().listen(emitted.add);

      await repository.sync();
      await pumpEventQueue();
      await subscription.cancel();

      expect(emitted, hasLength(1));
    });
  });

  group('the source (fake Firestore)', () {
    test('asks for documents updated after the given time, or all', () async {
      final firestore = FakeFirebaseFirestore();
      final exercises = firestore.collection('exercises');
      for (final day in [1, 2, 3]) {
        await exercises
            .doc('d$day')
            .set(document(popularity: day, updatedAt: at(day)));
      }
      final source = FirestoreExerciseSource(firestore);

      List<String> idsOf(List<ExerciseDocument> docs) =>
          [for (final doc in docs) doc.id]..sort();
      expect(idsOf(await source.changedSince(null)), ['d1', 'd2', 'd3']);
      expect(idsOf(await source.changedSince(at(2))), ['d3']);
      expect(await source.changedSince(at(3)), isEmpty);
    });
  });

  // The fake has no offline cache: Source.cache reads the same data as the
  // server and it cannot go offline, so cache-versus-server behaviour is
  // tested against a mocked source.
  group('cache and server (mocked source)', () {
    late MockSource source;
    late FirestoreExerciseRepository repository;

    ExerciseDocument doc(
      String id, {
      String status = 'live',
      int popularity = 1,
      required int day,
    }) => (
      id: id,
      data: document(
        status: status,
        popularity: popularity,
        updatedAt: at(day),
      ),
    );

    final offline = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    setUpAll(() => registerFallbackValue(at(1)));

    setUp(() {
      source = MockSource();
      repository = FirestoreExerciseRepository(source);
    });

    test('an empty cache fetches everything', () async {
      when(() => source.cached()).thenAnswer((_) async => []);
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('a', day: 1)]);

      await repository.sync();

      verify(() => source.changedSince(null)).called(1);
      expect(ids(await repository.watchExercises().first), ['a']);
    });

    test(
      'a filled cache asks only for what is newer than its newest',
      () async {
        when(() => source.cached()).thenAnswer(
          (_) async => [doc('a', day: 3), doc('b', popularity: 2, day: 5)],
        );
        when(() => source.changedSince(any()))
            .thenAnswer((_) async => [doc('a', status: 'retired', day: 6)]);

        final result = await repository.sync();

        expect(result.isOk, isTrue);
        verify(() => source.changedSince(at(5))).called(1);
        expect(ids(await repository.watchExercises().first), ['b']);
      },
    );

    test(
      'offline, the cached list stays and sync reports a network failure',
      () async {
        when(() => source.cached()).thenAnswer(
          (_) async => [doc('a', day: 1), doc('r', status: 'retired', day: 1)],
        );
        when(() => source.changedSince(any())).thenThrow(offline);

        final result = await repository.sync();

        expect(result.failureOrNull, isA<NetworkFailure>());
        expect(ids(await repository.watchExercises().first), ['a']);
      },
    );

    test(
      'offline with an empty cache, the list is empty, not pending',
      () async {
        when(() => source.cached()).thenAnswer((_) async => []);
        when(() => source.changedSince(any())).thenThrow(offline);

        final result = await repository.sync();

        expect(result.failureOrNull, isA<NetworkFailure>());
        expect(await repository.watchExercises().first, isEmpty);
      },
    );

    test('an unreadable cache falls back to a full fetch', () async {
      when(() => source.cached()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'internal'),
      );
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('a', day: 1)]);

      expect((await repository.sync()).isOk, isTrue);
      verify(() => source.changedSince(null)).called(1);
    });

    test('calls during a running sync share it', () async {
      final cache = Completer<List<ExerciseDocument>>();
      when(() => source.cached()).thenAnswer((_) => cache.future);
      when(() => source.changedSince(any())).thenAnswer((_) async => []);

      final first = repository.sync();
      final second = repository.sync();
      cache.complete([doc('a', day: 1)]);
      await Future.wait([first, second]);

      verify(() => source.cached()).called(1);
      verify(() => source.changedSince(any())).called(1);
    });

    test('watchers that join later get the current list first', () async {
      when(() => source.cached()).thenAnswer((_) async => []);
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('a', day: 1)]);
      await repository.sync();

      when(() => source.cached()).thenAnswer((_) async => [doc('a', day: 1)]);
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('b', popularity: 0, day: 2)]);
      final expectation = expectLater(
        repository.watchExercises().map(ids),
        emitsInOrder([
          ['a'],
          ['b', 'a'],
        ]),
      );
      await repository.sync();
      await expectation;
    });
  });
}
