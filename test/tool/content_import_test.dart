import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/content_validator.dart';
import '../../tool/src/content_import.dart';

void main() {
  group('encodeValue', () {
    test('encodes scalars', () {
      expect(encodeValue(null), {'nullValue': null});
      expect(encodeValue(true), {'booleanValue': true});
      expect(encodeValue('a'), {'stringValue': 'a'});
    });

    test('keeps integers and doubles apart', () {
      expect(encodeValue(60), {'integerValue': '60'});
      expect(encodeValue(2.5), {'doubleValue': 2.5});
      expect(encodeValue(1.0), {'doubleValue': 1.0});
    });

    test('encodes arrays and nested maps', () {
      expect(encodeValue(<Object?>[]), {'arrayValue': <String, Object?>{}});
      expect(encodeValue(<String, Object?>{}), {
        'mapValue': <String, Object?>{},
      });
      expect(
        encodeValue({
          'l10n': {
            'en': {
              'cues': ['Slow'],
            },
          },
        }),
        {
          'mapValue': {
            'fields': {
              'l10n': {
                'mapValue': {
                  'fields': {
                    'en': {
                      'mapValue': {
                        'fields': {
                          'cues': {
                            'arrayValue': {
                              'values': [
                                {'stringValue': 'Slow'},
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      );
    });

    test('rejects arrays inside arrays', () {
      expect(
        () => encodeValue([
          ['dumbbell'],
        ]),
        throwsArgumentError,
      );
    });
  });

  group('exerciseContent', () {
    test('drops the id and stores alternative sets as maps', () {
      final content = exerciseContent({
        'id': 'ex_a',
        'equipment': ['barbell'],
        'equipmentAlternatives': [
          ['dumbbell', 'bench'],
          ['cable'],
        ],
      });

      expect(content.containsKey('id'), isFalse);
      expect(content['equipmentAlternatives'], [
        {
          'items': ['dumbbell', 'bench'],
        },
        {
          'items': ['cable'],
        },
      ]);
      expect(encodeFields(content)['equipmentAlternatives'], {
        'arrayValue': {
          'values': [
            {
              'mapValue': {
                'fields': {
                  'items': {
                    'arrayValue': {
                      'values': [
                        {'stringValue': 'dumbbell'},
                        {'stringValue': 'bench'},
                      ],
                    },
                  },
                },
              },
            },
            {
              'mapValue': {
                'fields': {
                  'items': {
                    'arrayValue': {
                      'values': [
                        {'stringValue': 'cable'},
                      ],
                    },
                  },
                },
              },
            },
          ],
        },
      });
    });

    test('stores incrementKg as a double and other numbers unchanged', () {
      final content = exerciseContent({
        'id': 'ex_a',
        'incrementKg': 1,
        'defaultRestS': 60,
      });
      final fields = encodeFields(content);

      expect(fields['incrementKg'], {'doubleValue': 1.0});
      expect(fields['defaultRestS'], {'integerValue': '60'});
      expect(
        encodeFields(exerciseContent({'incrementKg': 2.5}))['incrementKg'],
        {'doubleValue': 2.5},
      );
    });

    test('encodes the whole library without errors', () {
      final report = validateContent(Directory('content/exercises'));
      for (final e in report.exercises) {
        final doc = ContentDoc.exercise(e.data);
        expect(doc.fields['contentHash'], {'stringValue': doc.hash});
        expect(doc.fields.containsKey('id'), isFalse);
      }
    });
  });

  group('contentHash', () {
    final content = {
      'family': 'curl',
      'l10n': {
        'en': {
          'name': 'Curl',
          'cues': ['Slow'],
        },
      },
    };

    test('ignores key order at every level', () {
      final reordered = {
        'l10n': {
          'en': {
            'cues': ['Slow'],
            'name': 'Curl',
          },
        },
        'family': 'curl',
      };
      expect(contentHash(reordered), contentHash(content));
      expect(contentHash(content), hasLength(64));
    });

    test('changes when content changes', () {
      final changed = {
        ...content,
        'l10n': {
          'en': {
            'name': 'Curl',
            'cues': ['Slower'],
          },
        },
      };
      expect(contentHash(changed), isNot(contentHash(content)));
      expect(
        contentHash({'incrementKg': 1}),
        isNot(contentHash({'incrementKg': 1.0})),
      );
    });

    test('is not affected by the id', () {
      expect(
        ContentDoc.exercise({'id': 'ex_a', 'family': 'f'}).hash,
        ContentDoc.exercise({'id': 'ex_b', 'family': 'f'}).hash,
      );
    });
  });

  group('decodeValue', () {
    test('reverses encodeValue for every content type', () {
      final value = {
        'n': null,
        'b': false,
        'i': 60,
        'd': 2.5,
        'whole': 1.0,
        's': 'x',
        'empty': <Object?>[],
        'emptyMap': <String, Object?>{},
        'alts': [
          {
            'items': ['dumbbell'],
          },
        ],
      };
      final decoded = decodeValue(encodeValue(value));

      expect(decoded, value);
      expect((decoded! as Map)['whole'], isA<double>());
      expect((decoded as Map)['i'], isA<int>());
    });

    test('reads doubles sent as JSON integers or strings', () {
      expect(decodeValue({'doubleValue': 1}), isA<double>());
      expect(decodeValue({'doubleValue': 'NaN'}), isNaN);
      expect(decodeValue({'integerValue': '7'}), 7);
    });

    test('keeps unknown types apart from content', () {
      expect(decodeValue({'timestampValue': '2026-01-01T00:00:00Z'}), {
        'timestampValue': '2026-01-01T00:00:00Z',
      });
    });

    test('a stored exercise hashes the same as its file', () {
      final report = validateContent(Directory('content/exercises'));
      for (final e in report.exercises) {
        final doc = ContentDoc.exercise(e.data);
        final stored = {
          ...doc.fields,
          'updatedAt': {'timestampValue': '2026-11-11T10:00:00Z'},
        };
        final remote = RemoteDocument.fromFields(decodeFields(stored), 't');
        expect(remote.actualHash, doc.hash, reason: e.id);
        expect(remote.editedElsewhere, isFalse, reason: e.id);
      }
    });
  });

  group('RemoteDocument', () {
    final doc = ContentDoc('exercises/ex_a', {
      'status': 'live',
      'defaultRestS': 60,
    });

    RemoteDocument stored(Map<String, Object?> fields) =>
        RemoteDocument.fromFields(decodeFields(encodeFields(fields)), 't');

    test('is not edited when its content matches contentHash', () {
      final remote = stored({...doc.content, 'contentHash': doc.hash});
      expect(remote.editedElsewhere, isFalse);
    });

    test('is edited when content changed but contentHash did not', () {
      final remote = stored({
        ...doc.content,
        'defaultRestS': 90,
        'contentHash': doc.hash,
      });
      expect(remote.editedElsewhere, isTrue);
    });

    test('is edited when it has no contentHash', () {
      expect(stored(doc.content).editedElsewhere, isTrue);
    });

    test('a whole increment stored as an integer hashes like the file', () {
      // The admin panel writes from the web, where 2.0 becomes an integer.
      final file = ContentDoc.exercise({
        'id': 'ex_a',
        'loggingType': 'weight_reps',
        'incrementKg': 2.0,
      });
      final fields = {
        ...file.fields,
        'incrementKg': {'integerValue': '2'},
      };
      final remote = RemoteDocument.fromFields(decodeFields(fields), 't');
      expect(remote.actualHash, file.hash);
      expect(remote.editedElsewhere, isFalse);
    });
  });

  group('planImport', () {
    RemoteDocument remote(String stored, String actual) =>
        RemoteDocument(storedHash: stored, actualHash: actual, updateTime: 't');

    final local = {
      'ex_new': 'h1',
      'ex_same': 'h2',
      'ex_changed': 'h3',
      'ex_edited': 'h4',
      'ex_edited_to_file': 'h5',
    };
    final existing = {
      'ex_same': remote('h2', 'h2'),
      'ex_changed': remote('old', 'old'),
      'ex_edited': remote('old', 'panel'),
      'ex_edited_to_file': remote('old', 'h5'),
      'ex_gone': remote('h', 'h'),
    };

    test('sorts exercises into new, changed, unchanged, edited, orphaned', () {
      final plan = planImport(local, existing);

      expect(plan.created, ['ex_new']);
      expect(plan.updated, ['ex_changed', 'ex_edited_to_file']);
      expect(plan.unchanged, ['ex_same']);
      expect(plan.edited, ['ex_edited']);
      expect(plan.orphaned, ['ex_gone']);
      expect(plan.skipped, ['ex_edited']);
      expect(plan.toWrite, ['ex_changed', 'ex_edited_to_file', 'ex_new']);
    });

    test('overwrites edited exercises only with force', () {
      final plan = planImport(local, existing, force: true);

      expect(plan.edited, ['ex_edited']);
      expect(plan.skipped, isEmpty);
      expect(plan.toWrite, [
        'ex_changed',
        'ex_edited',
        'ex_edited_to_file',
        'ex_new',
      ]);
    });
  });

  group('programDocs', () {
    final program = {
      'id': 'pr_a',
      'status': 'live',
      'premium': true,
      'order': 3,
      'minutes': {'min': 6, 'max': 6},
      'l10n': {
        'en': {'name': 'A', 'summary': 'A program.'},
      },
      'days': [
        {
          'name': 'Day 1',
          'items': [
            {
              'exerciseId': 'ex_a',
              'sets': 3,
              'repMin': 8,
              'repMax': 12,
              'restS': 60,
            },
          ],
        },
      ],
    };
    Map<String, Object?> edited(void Function(Map<String, Object?>) change) {
      final copy = jsonDecode(jsonEncode(program)) as Map<String, Object?>;
      change(copy);
      return copy;
    }

    test('splits a program into its card and its days', () {
      final (:card, :detail) = programDocs(program);

      expect(card.path, 'programs/pr_a');
      expect(card.content.keys, [
        'status',
        'premium',
        'order',
        'minutes',
        'l10n',
      ]);
      expect(card.fields['minutes'], {
        'mapValue': {
          'fields': {
            'min': {'integerValue': '6'},
            'max': {'integerValue': '6'},
          },
        },
      });
      expect(detail.path, 'programs/pr_a/detail/main');
      expect(detail.content, {'days': program['days']});
      expect(card.hash, contentHash(card.content));
      expect(detail.hash, contentHash(detail.content));
      expect(detail.fields['contentHash'], {'stringValue': detail.hash});
    });

    test('a card change leaves the detail hash alone, and back', () {
      final docs = programDocs(program);
      final renamed = programDocs(edited((p) => p['order'] = 4));
      final moreSets = programDocs(
        edited(
          (p) =>
              (((p['days']! as List).first! as Map)['items']! as List)
                      .cast<Map<String, Object?>>()
                      .first['sets'] =
                  4,
        ),
      );

      expect(renamed.card.hash, isNot(docs.card.hash));
      expect(renamed.detail.hash, docs.detail.hash);
      expect(moreSets.card.hash, docs.card.hash);
      expect(moreSets.detail.hash, isNot(docs.detail.hash));
    });

    test('every program file encodes and hashes like its stored form', () {
      final report = validateContent(
        Directory('content/exercises'),
        programs: Directory('content/programs'),
      );
      expect(report.programs, isNotEmpty);
      for (final p in report.programs) {
        final (:card, :detail) = programDocs(p.data);
        for (final doc in [card, detail]) {
          final stored = {
            ...doc.fields,
            'updatedAt': {'timestampValue': '2026-11-11T10:00:00Z'},
          };
          final remote = RemoteDocument.fromFields(decodeFields(stored), 't');
          expect(remote.actualHash, doc.hash, reason: doc.path);
          expect(remote.editedElsewhere, isFalse, reason: doc.path);
        }
      }
    });

    test('a detail edited elsewhere no longer matches its contentHash', () {
      final (:card, :detail) = programDocs(program);
      final fields = decodeFields(detail.fields);
      (((fields['days']! as List).first! as Map)['items']! as List)
              .cast<Map<String, Object?>>()
              .first['restS'] =
          90;

      expect(RemoteDocument.fromFields(fields, 't').editedElsewhere, isTrue);
      expect(
        RemoteDocument.fromFields(
          decodeFields(card.fields),
          't',
        ).editedElsewhere,
        isFalse,
      );
    });
  });

  group('planImport holds a program back as one unit', () {
    RemoteDocument remote(String stored, String actual) =>
        RemoteDocument(storedHash: stored, actualHash: actual, updateTime: 't');

    final local = {
      'programs/pr_a': 'card-new',
      'programs/pr_a/detail/main': 'days',
      'programs/pr_b': 'card',
      'programs/pr_b/detail/main': 'days-new',
    };
    final existing = {
      // pr_a: the detail was edited in the panel, the card changed in the
      // file. pr_b: the card was edited in the panel, the days changed.
      'programs/pr_a': remote('card', 'card'),
      'programs/pr_a/detail/main': remote('days-old', 'panel'),
      'programs/pr_b': remote('card-old', 'panel'),
      'programs/pr_b/detail/main': remote('days', 'days'),
    };

    test('either document edited elsewhere skips both', () {
      final plan = planImport(local, existing);

      expect(plan.edited, ['programs/pr_a/detail/main', 'programs/pr_b']);
      expect(plan.held, ['programs/pr_a', 'programs/pr_b/detail/main']);
      expect(plan.updated, isEmpty);
      expect(plan.toWrite, isEmpty);
    });

    test('force writes both', () {
      final plan = planImport(local, existing, force: true);

      expect(plan.held, isEmpty);
      expect(plan.toWrite, local.keys.toList()..sort());
    });

    test('an edited exercise holds back nothing else', () {
      final plan = planImport(
        {'exercises/ex_a': 'new', 'exercises/ex_b': 'new'},
        {
          'exercises/ex_a': remote('old', 'panel'),
          'exercises/ex_b': remote('old', 'old'),
        },
      );
      expect(plan.held, isEmpty);
      expect(plan.toWrite, ['exercises/ex_b']);
    });
  });

  test('planImport sorts program documents like exercises', () {
    RemoteDocument remote(String stored, String actual) =>
        RemoteDocument(storedHash: stored, actualHash: actual, updateTime: 't');

    final plan = planImport(
      {
        'exercises/ex_a': 'e1',
        'programs/pr_new': 'c1',
        'programs/pr_new/detail/main': 'd1',
        'programs/pr_same': 'c2',
        'programs/pr_same/detail/main': 'd2',
        'programs/pr_edited': 'c3',
        'programs/pr_edited/detail/main': 'd3',
      },
      {
        'exercises/ex_a': remote('e1', 'e1'),
        'programs/pr_same': remote('c2', 'c2'),
        'programs/pr_same/detail/main': remote('old', 'old'),
        'programs/pr_edited': remote('c3', 'c3'),
        'programs/pr_edited/detail/main': remote('old', 'panel'),
        'programs/pr_gone': remote('c', 'c'),
      },
    );

    expect(plan.created, ['programs/pr_new', 'programs/pr_new/detail/main']);
    expect(plan.updated, ['programs/pr_same/detail/main']);
    expect(plan.unchanged, [
      'exercises/ex_a',
      'programs/pr_edited',
      'programs/pr_same',
    ]);
    expect(plan.edited, ['programs/pr_edited/detail/main']);
    expect(plan.orphaned, ['programs/pr_gone']);
    // Exercises sort before programs, and a card before its detail.
    expect(plan.toWrite, [
      'programs/pr_new',
      'programs/pr_new/detail/main',
      'programs/pr_same/detail/main',
    ]);
  });

  group('packUnits', () {
    test('fills batches up to the size, in order', () {
      expect(packUnits<int>([]), isEmpty);
      expect(
        packUnits([
          for (var i = 0; i < 1001; i++) [i],
        ]).map((b) => b.length),
        [500, 500, 1],
      );
    });

    test('never splits a unit across batches', () {
      expect(
        packUnits([
          [1],
          [2, 3],
          [4, 5],
          [6],
        ], size: 2),
        [
          [1],
          [2, 3],
          [4, 5],
          [6],
        ],
      );
      expect(
        packUnits([
          [1],
          [2],
          [3, 4],
        ], size: 3),
        [
          [1, 2],
          [3, 4],
        ],
      );
    });

    test('rejects a unit larger than a batch', () {
      expect(
        () => packUnits([
          [1, 2, 3],
        ], size: 2),
        throwsArgumentError,
      );
    });
  });

  test('groupByUnit keeps a card with its detail', () {
    expect(importUnit('programs/pr_a/detail/main'), 'programs/pr_a');
    expect(importUnit('exercises/ex_a'), 'exercises/ex_a');
    expect(
      groupByUnit([
        'exercises/ex_a',
        'programs/pr_a',
        'programs/pr_a/detail/main',
        'programs/pr_b/detail/main',
      ]),
      [
        ['exercises/ex_a'],
        ['programs/pr_a', 'programs/pr_a/detail/main'],
        ['programs/pr_b/detail/main'],
      ],
    );
  });

  group('contentWrite', () {
    final doc = ContentDoc('exercises/ex_a', {'status': 'live'});
    const db = 'projects/p/databases/(default)';

    test('creates only if the document does not exist', () {
      expect(contentWrite(db, doc), {
        'update': {
          'name': '$db/documents/exercises/ex_a',
          'fields': {
            'status': {'stringValue': 'live'},
            'contentHash': {'stringValue': doc.hash},
          },
        },
        'updateTransforms': [
          {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
        ],
        'currentDocument': {'exists': false},
      });
    });

    test('writes a program detail at its subcollection path', () {
      final detail = ContentDoc('programs/pr_a/detail/main', {'days': []});
      expect(
        (contentWrite(db, detail)['update']! as Map)['name'],
        '$db/documents/programs/pr_a/detail/main',
      );
    });

    test('updates only if the document is unchanged since the read', () {
      final write = contentWrite(db, doc, updateTime: '2026-11-11T10:00:00Z');
      expect(write['currentDocument'], {'updateTime': '2026-11-11T10:00:00Z'});
    });
  });
}
