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

  test('batches split at 500 writes', () {
    expect(batches(<int>[]), isEmpty);
    expect(batches(List.filled(500, 0)).map((b) => b.length), [500]);
    expect(batches(List.filled(1001, 0)).map((b) => b.length), [500, 500, 1]);
  });

  group('exerciseWrite', () {
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

    test('updates only if the document is unchanged since the read', () {
      final write = contentWrite(db, doc, updateTime: '2026-11-11T10:00:00Z');
      expect(write['currentDocument'], {'updateTime': '2026-11-11T10:00:00Z'});
    });
  });
}
