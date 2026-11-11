import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/content_validator.dart';
import '../../tool/src/exercise_import.dart';

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
        final doc = ExerciseDoc.fromJson(e.data);
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
        ExerciseDoc.fromJson({'id': 'ex_a', 'family': 'f'}).hash,
        ExerciseDoc.fromJson({'id': 'ex_b', 'family': 'f'}).hash,
      );
    });
  });

  test('planImport sorts exercises into new, changed, unchanged, orphaned', () {
    final plan = planImport(
      {'ex_new': 'h1', 'ex_same': 'h2', 'ex_changed': 'h3', 'ex_nohash': 'h4'},
      {'ex_same': 'h2', 'ex_changed': 'old', 'ex_nohash': null, 'ex_gone': 'h'},
    );

    expect(plan.created, ['ex_new']);
    expect(plan.updated, ['ex_changed', 'ex_nohash']);
    expect(plan.unchanged, ['ex_same']);
    expect(plan.orphaned, ['ex_gone']);
    expect(plan.toWrite, ['ex_changed', 'ex_new', 'ex_nohash']);
  });

  test('batches split at 500 writes', () {
    expect(batches(<int>[]), isEmpty);
    expect(batches(List.filled(500, 0)).map((b) => b.length), [500]);
    expect(batches(List.filled(1001, 0)).map((b) => b.length), [500, 500, 1]);
  });

  test('exerciseWrite replaces the document and stamps updatedAt', () {
    final doc = ExerciseDoc('ex_a', {'status': 'live'});
    final write = exerciseWrite('projects/p/databases/(default)', doc);

    expect(write, {
      'update': {
        'name': 'projects/p/databases/(default)/documents/exercises/ex_a',
        'fields': {
          'status': {'stringValue': 'live'},
          'contentHash': {'stringValue': doc.hash},
        },
      },
      'updateTransforms': [
        {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
      ],
    });
  });
}
