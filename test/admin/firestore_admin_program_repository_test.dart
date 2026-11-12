import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/programs/data/firestore_admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/data/firestore_catalogue_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../tool/src/content_import.dart';

import 'program_fixtures.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreAdminProgramRepository repository;
  final importedAt = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
  const id = 'pr_dumbbell_basics';

  DocumentReference<Map<String, dynamic>> card([String programId = id]) =>
      firestore.collection('programs').doc(programId);
  DocumentReference<Map<String, dynamic>> detail([String programId = id]) =>
      card(programId).collection('detail').doc('main');

  /// The program as the import stores it, plus fields the panel does not
  /// know.
  Future<void> seedImported() async {
    final json = programJson();
    await card().set({
      ...cardOf(json)..remove('id'),
      'contentHash': 'card-hash',
      'reviewNote': 'kept',
      'updatedAt': importedAt,
    });
    await detail().set({
      'days': json['days'],
      'contentHash': 'detail-hash',
      'updatedAt': importedAt,
    });
  }

  Future<ProgramRecord> load() async =>
      (await repository.load(id)).valueOrNull!;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreAdminProgramRepository(firestore);
  });

  group('load', () {
    test('reads the card and its days in the content-file shape', () async {
      await seedImported();
      final record = await load();
      expect(record.version, (
        card: importedAt.toDate(),
        detail: importedAt.toDate(),
      ));
      expect(record.json, isNot(contains('contentHash')));
      expect(record.json, isNot(contains('updatedAt')));
      expect(record.json['reviewNote'], 'kept');
      expect(record.draft, ProgramDraft.fromJson(programJson()));
    });

    test('reads whole numbers stored as doubles as integers', () async {
      await seedImported();
      final json = programJson();
      final days = json['days']! as List<Object?>;
      final day = days.first! as Map<String, Object?>;
      final item = (day['items']! as List<Object?>).first!;
      await card().update({'order': 1.0, 'minutes.min': 4.0});
      await detail().update({
        'days': [
          {
            ...day,
            'items': [
              {...item as Map<String, Object?>, 'sets': 3.0},
            ],
          },
        ],
      });
      final record = await load();
      expect(record.json['order'], isA<int>());
      expect(record.draft.order, 1);
      expect(record.draft.days.single.items.single.sets, 3);
    });

    test('a program without a card is a NotFoundFailure', () async {
      final result = await repository.load('pr_missing');
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('a card without its detail reads with no days', () async {
      await seedImported();
      await detail().delete();
      final record = await load();
      expect(record.draft.days, isEmpty);
      expect(record.version.detail, isNull);
    });
  });

  test('watchCards emits every status, without the days', () async {
    await seedImported();
    await card('pr_old').set({
      ...cardOf(programJson(id: 'pr_old', status: 'retired'))..remove('id'),
      'updatedAt': importedAt,
    });
    final records = await repository.watchCards().first;
    expect(
      {for (final r in records) r.id: r.draft.status},
      {id: ExerciseStatus.live, 'pr_old': ExerciseStatus.retired},
    );
    expect(records.first.json, isNot(contains('days')));
    expect(records.first.daysPerWeek, 2);
  });

  group('create', () {
    test('writes the card and the detail as the import does', () async {
      final json = programJson();

      // As the editor saves the program of this file.
      final result = await repository.create(
        ProgramDraft.fromJson(json).content(exercises),
      );

      final stored = (await card().get()).data()!;
      final storedDetail = (await detail().get()).data()!;
      expect(stored['updatedAt'], isA<Timestamp>());
      expect(storedDetail['updatedAt'], isA<Timestamp>());
      // The import's documents of the same file, without contentHash.
      final docs = programDocs(json);
      expect(Map.of(stored)..remove('updatedAt'), docs.card.content);
      expect(Map.of(storedDetail)..remove('updatedAt'), docs.detail.content);
      // The app reads the card.
      final read = FirestoreCatalogueRepository.catalogueProgramFromMap(
        id,
        stored,
      )!;
      expect(read.daysPerWeek, 2);
      expect(read.minutes, (min: 8, max: 11));
      expect(read.equipment, [Equipment.dumbbell, Equipment.bench]);
      expect(read.equipmentProfile, EquipmentProfile.dumbbells);
      expect(read.text('en').name, 'Dumbbell Basics');
      final saved = result.valueOrNull! as ProgramSaved;
      expect(saved.record!.draft, ProgramDraft.fromJson(json));
    });

    test('refuses an id that is taken', () async {
      await seedImported();
      final result = await repository.create(programJson(name: 'Other'));
      expect(result.valueOrNull, const ProgramIdTaken());
      final stored = (await card().get()).data()!;
      expect(stored['l10n']['en']['name'], 'Dumbbell Basics');
    });
  });

  group('update', () {
    test(
      'writes card and detail, keeping contentHash and unknown fields',
      () async {
        await seedImported();
        await card().update({
          'l10n.de': {'name': 'Kurzhantel-Basis'},
          'l10n.en.subtitle': 'kept',
        });
        final loaded = await load();
        final days = [...loaded.draft.days]..removeLast();
        final edited = loaded.draft
            .copyWith(premium: true, lengthWeeks: null, days: days)
            .withText(
              'en',
              const CatalogueText(
                name: 'Dumbbell Start',
                summary: 'A press and a curl. Once a week.',
              ),
            );

        final result = await repository.update(
          edited.content(exercises),
          loaded: loaded.version,
        );

        final stored = (await card().get()).data()!;
        expect(stored['premium'], isTrue);
        expect(stored['daysPerWeek'], 1);
        expect(stored, isNot(contains('lengthWeeks')));
        expect(stored['l10n'], {
          'de': {'name': 'Kurzhantel-Basis'},
          'en': {
            'name': 'Dumbbell Start',
            'summary': 'A press and a curl. Once a week.',
            'subtitle': 'kept',
          },
        });
        // The import's hashes stay, so it sees the program as edited here.
        expect(stored['contentHash'], 'card-hash');
        expect(stored['reviewNote'], 'kept');
        expect(stored['updatedAt'], isNot(importedAt));
        final storedDetail = (await detail().get()).data()!;
        expect(storedDetail['contentHash'], 'detail-hash');
        expect(storedDetail['days'], hasLength(1));
        expect(storedDetail['updatedAt'], isNot(importedAt));

        final saved = (result.valueOrNull! as ProgramSaved).record!;
        expect(saved.draft, edited);
        expect(saved.version.card, (stored['updatedAt'] as Timestamp).toDate());
      },
    );

    test('refuses when the card changed since it was loaded', () async {
      await seedImported();
      final loaded = await load();
      await card().update({
        'order': 7,
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 2)),
      });

      final result = await repository.update(
        loaded.draft.copyWith(order: 3).content(exercises),
        loaded: loaded.version,
      );

      expect(result.valueOrNull, const ProgramChangedSinceLoaded());
      expect((await card().get()).data()!['order'], 7);
    });

    test('refuses when only the detail changed since it was loaded', () async {
      await seedImported();
      final loaded = await load();
      // The import rewrites only the days.
      await detail().update({
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 2)),
      });

      final result = await repository.update(
        loaded.draft.copyWith(order: 3).content(exercises),
        loaded: loaded.version,
      );

      expect(result.valueOrNull, const ProgramChangedSinceLoaded());
      expect((await card().get()).data()!['order'], 1);
    });

    test('refuses when the program was deleted since it was loaded', () async {
      await seedImported();
      final loaded = await load();
      await card().delete();

      final result = await repository.update(
        loaded.draft.content(exercises),
        loaded: loaded.version,
      );

      expect(result.valueOrNull, const ProgramChangedSinceLoaded());
      expect((await card().get()).exists, isFalse);
    });
  });

  test(
    'a write that committed is saved even when reading it back fails',
    () async {
      final firestore = MockFirestore();
      // The read after the write finds nothing in this empty store, which
      // stands for any failed read.
      when(() => firestore.collection('programs'))
          .thenReturn(FakeFirebaseFirestore().collection('programs'));
      when(() => firestore.runTransaction<ProgramSaveOutcome?>(any()))
          .thenAnswer((_) async => null);

      final result = await FirestoreAdminProgramRepository(firestore)
          .create(programJson());

      expect(result.valueOrNull, const ProgramSaved(null));
    },
  );

  test('a write the rules deny is a PermissionFailure', () async {
    final denying = MockFirestore();
    when(() => denying.collection('programs'))
        .thenReturn(FakeFirebaseFirestore().collection('programs'));
    when(() => denying.runTransaction<ProgramSaveOutcome?>(any())).thenThrow(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );

    final result = await FirestoreAdminProgramRepository(denying)
        .create(programJson());

    expect(result.failureOrNull, isA<PermissionFailure>());
  });
}
