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

    test('edits to draft or retired documents emit nothing new', () async {
      await repository.sync();
      final emitted = <List<Exercise>>[];
      final subscription = repository.watchExercises().listen(emitted.add);
      final exercises = firestore.collection('exercises');
      await exercises.doc('draft').update({
        'popularity': 0,
        'updatedAt': at(5),
      });
      await exercises.doc('retired').update({'updatedAt': at(6)});

      expect((await repository.sync()).isOk, isTrue);
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

    /// Emissions of [repository] while [body] runs.
    Future<List<List<String>>> emissionsDuring(
      Future<void> Function() body,
    ) async {
      final emitted = <List<String>>[];
      final subscription = repository.watchExercises().listen(
        (list) => emitted.add(ids(list)),
      );
      await body();
      await pumpEventQueue();
      await subscription.cancel();
      return emitted;
    }

    setUpAll(() => registerFallbackValue(at(1)));

    setUp(() {
      source = MockSource();
      repository = FirestoreExerciseRepository(source);
    });

    test('an empty cache fetches everything once', () async {
      when(() => source.cached()).thenAnswer((_) async => []);
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('a', day: 1)]);
      when(() => source.serverCount()).thenAnswer((_) async => 1);

      expect((await repository.sync()).isOk, isTrue);

      verify(() => source.changedSince(null)).called(1);
      expect(ids(await repository.watchExercises().first), ['a']);
    });

    test(
      'a full cache asks only for what is newer, with no full fetch',
      () async {
        when(() => source.cached()).thenAnswer(
          (_) async => [doc('a', day: 3), doc('b', popularity: 2, day: 5)],
        );
        when(() => source.changedSince(any()))
            .thenAnswer((_) async => [doc('a', status: 'retired', day: 6)]);
        when(() => source.serverCount()).thenAnswer((_) async => 2);

        expect((await repository.sync()).isOk, isTrue);

        verify(() => source.changedSince(at(5))).called(1);
        verifyNever(() => source.changedSince(null));
        expect(ids(await repository.watchExercises().first), ['b']);
      },
    );

    test('a cache missing older documents is rebuilt in full', () async {
      // The newest document is cached, so the incremental fetch finds
      // nothing; only the count shows that 'a' and 'r' are missing.
      when(() => source.cached())
          .thenAnswer((_) async => [doc('b', popularity: 2, day: 5)]);
      when(() => source.changedSince(at(5))).thenAnswer((_) async => []);
      when(() => source.serverCount()).thenAnswer((_) async => 3);
      when(() => source.changedSince(null)).thenAnswer(
        (_) async => [
          doc('a', day: 1),
          doc('b', popularity: 2, day: 5),
          doc('r', status: 'retired', day: 2),
        ],
      );

      final emitted = await emissionsDuring(() async {
        expect((await repository.sync()).isOk, isTrue);
      });

      verify(() => source.changedSince(null)).called(1);
      expect(emitted, [
        ['b'],
        ['a', 'b'],
      ]);
    });

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

    test('a count failing offline keeps the cached list', () async {
      when(() => source.cached()).thenAnswer((_) async => [doc('a', day: 1)]);
      when(() => source.changedSince(any())).thenAnswer((_) async => []);
      when(() => source.serverCount()).thenThrow(offline);

      late Result<void> result;
      final emitted = await emissionsDuring(
        () async => result = await repository.sync(),
      );

      expect(result.failureOrNull, isA<NetworkFailure>());
      verifyNever(() => source.changedSince(null));
      expect(emitted, [
        ['a'],
      ]);
    });

    test('offline with an empty cache, nothing is published', () async {
      when(() => source.cached()).thenAnswer((_) async => []);
      when(() => source.changedSince(any())).thenThrow(offline);

      late Result<void> result;
      final emitted = await emissionsDuring(
        () async => result = await repository.sync(),
      );

      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(emitted, isEmpty);
    });

    test('an empty catalogue on the server is published as empty', () async {
      when(() => source.cached()).thenAnswer((_) async => []);
      when(() => source.changedSince(any())).thenAnswer((_) async => []);
      when(() => source.serverCount()).thenAnswer((_) async => 0);

      final emitted = await emissionsDuring(repository.sync);

      expect(emitted, [<String>[]]);
    });

    test('an unreadable cache falls back to a full fetch', () async {
      when(() => source.cached()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'internal'),
      );
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('a', day: 1)]);
      when(() => source.serverCount()).thenAnswer((_) async => 1);

      expect((await repository.sync()).isOk, isTrue);
      verify(() => source.changedSince(null)).called(1);
    });

    test('equal popularity sorts by id', () async {
      when(() => source.cached()).thenAnswer(
        (_) async => [doc('c', day: 1), doc('a', day: 1), doc('b', day: 1)],
      );
      when(() => source.changedSince(any())).thenAnswer((_) async => []);
      when(() => source.serverCount()).thenAnswer((_) async => 3);

      await repository.sync();

      expect(ids(await repository.watchExercises().first), ['a', 'b', 'c']);
    });

    test('calls during a running sync share it', () async {
      final cache = Completer<List<ExerciseDocument>>();
      when(() => source.cached()).thenAnswer((_) => cache.future);
      when(() => source.changedSince(any())).thenAnswer((_) async => []);
      when(() => source.serverCount()).thenAnswer((_) async => 1);

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
      when(() => source.serverCount()).thenAnswer((_) async => 1);
      await repository.sync();

      when(() => source.cached()).thenAnswer((_) async => [doc('a', day: 1)]);
      when(() => source.changedSince(any()))
          .thenAnswer((_) async => [doc('b', popularity: 0, day: 2)]);
      when(() => source.serverCount()).thenAnswer((_) async => 2);
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
