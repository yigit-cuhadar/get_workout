import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/exercises/data/firestore_admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreAdminExerciseRepository repository;
  final importedAt = Timestamp.fromDate(DateTime.utc(2026, 11, 1));

  DocumentReference<Map<String, dynamic>> doc(String id) =>
      firestore.collection('exercises').doc(id);

  /// `ex_dumbbell_press` as the importer stores it, plus a field the panel
  /// does not know.
  Future<void> seedImported() => doc('ex_dumbbell_press').set({
    ...validJson()..remove('id'),
    'equipmentAlternatives': [
      {
        'items': ['kettlebell', 'bench'],
      },
    ],
    'contentHash': 'hash-from-import',
    'reviewNote': 'kept',
    'updatedAt': importedAt,
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreAdminExerciseRepository(firestore);
  });

  test('reads documents in the content-file shape', () async {
    await seedImported();
    final record = (await repository.load('ex_dumbbell_press')).valueOrNull!;
    expect(record.updatedAt, importedAt.toDate());
    expect(record.json['equipmentAlternatives'], [
      ['kettlebell', 'bench'],
    ]);
    expect(record.json, isNot(contains('contentHash')));
    expect(record.json, isNot(contains('updatedAt')));
    expect(record.json['reviewNote'], 'kept');
    expect(record.draft.equipmentAlternatives, [
      [Equipment.kettlebell, Equipment.bench],
    ]);
  });

  test('loading a missing document is a NotFoundFailure', () async {
    final result = await repository.load('ex_missing');
    expect(result.failureOrNull, isA<NotFoundFailure>());
  });

  test('watchAll emits every status', () async {
    await seedImported();
    await doc('ex_old').set({
      ...validJson(id: 'ex_old', name: 'Old', status: 'retired')
        ..remove('id')
        ..remove('equipmentAlternatives'),
      'updatedAt': importedAt,
    });
    final records = await repository.watchAll().first;
    expect(
      {for (final r in records) r.id: r.draft.status},
      {
        'ex_dumbbell_press': ExerciseStatus.live,
        'ex_old': ExerciseStatus.retired,
      },
    );
  });

  group('update', () {
    test('writes the managed fields in the stored shape', () async {
      await seedImported();
      final loaded = (await repository.load('ex_dumbbell_press')).valueOrNull!;
      final edited = loaded.draft.copyWith(
        incrementKg: 1.0,
        grip: null,
        equipmentAlternatives: [
          [Equipment.cable],
          [Equipment.resistanceBand],
        ],
        status: ExerciseStatus.retired,
      );

      final result = await repository.update(
        edited,
        loadedUpdatedAt: loaded.updatedAt,
      );

      final stored = (await doc('ex_dumbbell_press').get()).data()!;
      expect(stored['equipmentAlternatives'], [
        {
          'items': ['cable'],
        },
        {
          'items': ['resistance_band'],
        },
      ]);
      expect(stored['incrementKg'], isA<double>());
      expect(stored['incrementKg'], 1.0);
      expect(stored['status'], 'retired');
      expect(stored, isNot(contains('grip')));
      expect(stored, isNot(contains('id')));
      // The import's hash stays, so the import sees the document as edited
      // here; fields the panel does not manage stay too.
      expect(stored['contentHash'], 'hash-from-import');
      expect(stored['reviewNote'], 'kept');
      expect(stored['updatedAt'], isA<Timestamp>());
      expect(stored['updatedAt'], isNot(importedAt));

      final saved = result.valueOrNull! as Saved;
      expect(saved.record.draft, edited);
      expect(
        saved.record.updatedAt,
        (stored['updatedAt'] as Timestamp).toDate(),
      );
    });

    test('a whole number increment is still stored as a double', () async {
      await seedImported();
      final loaded = (await repository.load('ex_dumbbell_press')).valueOrNull!;
      await repository.update(
        loaded.draft.copyWith(incrementKg: 5.0),
        loadedUpdatedAt: loaded.updatedAt,
      );
      final stored = (await doc('ex_dumbbell_press').get()).data()!;
      expect(stored['incrementKg'], isA<double>());
    });

    test('keeps the text of other languages', () async {
      await seedImported();
      await doc('ex_dumbbell_press').update({
        'l10n.de': {'name': 'Kurzhanteldrücken'},
      });
      final loaded = (await repository.load('ex_dumbbell_press')).valueOrNull!;
      await repository.update(
        loaded.draft.copyWith(name: 'Flat Dumbbell Press'),
        loadedUpdatedAt: loaded.updatedAt,
      );
      final l10n = (await doc('ex_dumbbell_press').get()).data()!['l10n'];
      expect(l10n['de'], {'name': 'Kurzhanteldrücken'});
      expect(l10n['en']['name'], 'Flat Dumbbell Press');
    });

    test('refuses when the document changed since it was loaded', () async {
      await seedImported();
      final loaded = (await repository.load('ex_dumbbell_press')).valueOrNull!;
      // Someone else saves, or the import runs.
      await doc('ex_dumbbell_press').update({
        'popularity': 7,
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 2)),
      });

      final result = await repository.update(
        loaded.draft.copyWith(popularity: 3),
        loadedUpdatedAt: loaded.updatedAt,
      );

      expect(result.valueOrNull, const ChangedSinceLoaded());
      expect((await doc('ex_dumbbell_press').get()).data()!['popularity'], 7);
    });
  });

  test('a write the rules deny is a PermissionFailure', () async {
    final denying = MockFirestore();
    when(() => denying.collection('exercises'))
        .thenReturn(FakeFirebaseFirestore().collection('exercises'));
    when(() => denying.runTransaction<SaveOutcome?>(any())).thenThrow(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );

    final result = await FirestoreAdminExerciseRepository(denying)
        .create(ExerciseDraft.fromJson(validJson()));

    expect(result.failureOrNull, isA<PermissionFailure>());
  });

  group('create', () {
    test('writes a new document without contentHash', () async {
      final draft = ExerciseDraft.fromJson(validJson(id: 'ex_new'));

      final result = await repository.create(draft);

      final stored = (await doc('ex_new').get()).data()!;
      expect(stored, isNot(contains('contentHash')));
      expect(stored, isNot(contains('id')));
      expect(stored['updatedAt'], isA<Timestamp>());
      expect(stored['equipmentAlternatives'], [
        {
          'items': ['kettlebell', 'bench'],
        },
      ]);
      expect((result.valueOrNull! as Saved).record.draft, draft);
    });

    test('refuses an id that is taken', () async {
      await seedImported();
      final result = await repository.create(
        ExerciseDraft.fromJson(validJson(name: 'Other')),
      );
      expect(result.valueOrNull, const IdTaken());
      final stored = (await doc('ex_dumbbell_press').get()).data()!;
      expect(stored['l10n']['en']['name'], 'Dumbbell Press');
    });
  });
}
