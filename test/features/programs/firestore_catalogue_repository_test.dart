import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/data/firestore_catalogue_repository.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';

import '../../../tool/src/content_import.dart';

/// Every `content/programs/*.json`, by id.
Map<String, Map<String, Object?>> contentPrograms() => {
  for (final file in Directory(
    'content/programs',
  ).listSync().whereType<File>().where((file) => file.path.endsWith('.json')))
    for (final json in [
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    ])
      json['id']! as String: json,
};

/// [doc]'s fields as the importer stores them: encoded for Firestore,
/// decoded back, with the server's `updatedAt`.
Map<String, Object?> stored(ContentDoc doc) => {
  ...decodeFields(doc.fields),
  'updatedAt': Timestamp.fromDate(DateTime(2026, 11)),
};

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreCatalogueRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreCatalogueRepository(firestore);
  });

  Future<void> import(Map<String, Object?> json) async {
    final docs = programDocs(json);
    await firestore.doc(docs.card.path).set(stored(docs.card));
    await firestore.doc(docs.detail.path).set(stored(docs.detail));
  }

  group('the imported content', () {
    late Map<String, Map<String, Object?>> content;

    setUp(() async {
      content = contentPrograms();
      for (final json in content.values) {
        await import(json);
      }
    });

    test('lists every live program as a card, by order', () async {
      final cards = await repository.watchPrograms().first;
      final live = content.values.where((json) => json['status'] == 'live');

      expect(cards, hasLength(live.length));
      expect(cards.where((card) => !card.premium), hasLength(freePrograms));
      expect([
        for (final card in cards) card.order,
      ], [for (final json in live) json['order']! as int]..sort());
    });

    test('reads every card field as the file has it', () async {
      final cards = await repository.watchPrograms().first;

      for (final card in cards) {
        final json = content[card.id]!;
        final text = (json['l10n']! as Map)['en'] as Map;
        expect(card.premium, json['premium'], reason: card.id);
        expect(card.level.code, json['level'], reason: card.id);
        expect(card.goal.code, json['goal'], reason: card.id);
        expect(card.daysPerWeek, json['daysPerWeek'], reason: card.id);
        expect(card.lengthWeeks, json['lengthWeeks'], reason: card.id);
        expect(
          card.equipmentProfile.code,
          json['equipmentProfile'],
          reason: card.id,
        );
        expect(
          [for (final e in card.equipment) e.code],
          json['equipment'],
          reason: card.id,
        );
        expect(card.text('en').name, text['name'], reason: card.id);
        expect(card.text('en').summary, text['summary'], reason: card.id);
      }
    });

    test('reads the days as the content validator reads the file', () async {
      for (final MapEntry(key: id, value: json) in content.entries) {
        final days = await repository.getDays(id);

        expect(days.valueOrNull, ProgramEntry(json).program.days, reason: id);
      }
    });
  });

  group('cards', () {
    Map<String, Object?> card({Object? premium = false, Object? status}) => {
      'status': status ?? 'live',
      'premium': ?premium,
      'level': 'beginner',
      'goal': 'build_muscle',
      'daysPerWeek': 3,
      'equipment': ['dumbbell', 'bench', 'unknown'],
      'equipmentProfile': 'dumbbells',
      'order': 1,
      'l10n': {
        'en': {'name': 'Starter', 'summary': 'Simple.'},
      },
    };

    test('skips programs that are not live, or cannot be read', () async {
      await firestore.doc('programs/draft').set(card(status: 'draft'));
      await firestore.doc('programs/retired').set(card(status: 'retired'));
      await firestore.doc('programs/no_text').set({
        ...card(),
        'l10n': <String, Object?>{},
      });
      await firestore.doc('programs/no_level').set({
        ...card(),
        'level': 'expert',
      });
      await firestore.doc('programs/ok').set(card());

      final cards = await repository.watchPrograms().first;

      expect([for (final c in cards) c.id], ['ok']);
      expect(cards.single.equipment, [Equipment.dumbbell, Equipment.bench]);
      expect(cards.single.lengthWeeks, isNull);
    });

    test('is free only without premium or with exactly false', () async {
      await firestore.doc('programs/absent').set(card(premium: null));
      await firestore.doc('programs/false').set(card());
      await firestore.doc('programs/string').set(card(premium: 'false'));
      await firestore.doc('programs/true').set(card(premium: true));

      final cards = await repository.watchPrograms().first;

      expect(
        {for (final c in cards) c.id: c.premium},
        {'absent': false, 'false': false, 'string': true, 'true': true},
      );
    });

    test('follow changes', () async {
      final updates = repository.watchPrograms();
      await firestore.doc('programs/a').set(card());
      final expectation = expectLater(
        updates.map((cards) => [for (final c in cards) c.id]),
        emitsInOrder([
          ['a'],
          <String>[],
        ]),
      );
      await pumpEventQueue();
      await firestore.doc('programs/a').update({'status': 'retired'});
      await expectation;
    });
  });

  group('days', () {
    test('a program without days is not found', () async {
      final missing = await repository.getDays('nope');
      await firestore.doc('programs/empty/detail/main').set({'days': []});
      final empty = await repository.getDays('empty');

      expect(missing.failureOrNull, isA<NotFoundFailure>());
      expect(empty.failureOrNull, isA<NotFoundFailure>());
    });
  });
}
