import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/content_rules.dart';

import '../../tool/src/animation_validator.dart';
import '../../tool/src/content_validator.dart';

final library = {
  'ex_a': ExerciseEntry({
    'id': 'ex_a',
    'l10n': {
      'en': {
        'mistakes': ['one', 'two'],
      },
      'tr': {
        'mistakes': ['bir', 'iki'],
      },
    },
  }),
};

const kits = {
  'barbell': {'status': 'approved', 'pieces': <Object?>[]},
  'bench': {'status': 'draft', 'pieces': <Object?>[]},
};

Map<String, Object?> recipe({
  String status = 'approved',
  List<Object?> keys = const [
    [0, 'top'],
    [1.5, 'bottom'],
    [2, 'top'],
  ],
  List<String> gear = const ['barbell'],
  List<Object?> mistakes = const [],
}) => {
  'status': status,
  'view': [20, 10],
  'poses': {'top': <String, Object?>{}, 'bottom': <String, Object?>{}},
  'keys': keys,
  'gear': [
    for (final kit in gear) {'kit': kit},
  ],
  'mistakes': mistakes,
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('animations'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String name, Object? json) =>
      File('${dir.path}/$name').writeAsStringSync(jsonEncode(json));

  List<String> errors() {
    final errors = <String>[];
    validateAnimations(dir, library, errors);
    return errors;
  }

  test('the content passes', () {
    final report = validateContent(
      Directory('content/exercises'),
      animations: Directory('content/animations'),
    );

    expect(report.errors, isEmpty);
    expect(report.animations!.recipes, isNotEmpty);
  });

  test('a valid recipe passes', () {
    write('_kits.json', kits);
    write(
      'ex_a.json',
      recipe(
        mistakes: [
          {
            'line': 0,
            'status': 'draft',
            'poses': {'sag': <String, Object?>{}},
            'keys': [
              [0, 'top'],
              [1, 'sag'],
              [2, 'top'],
            ],
          },
          {'line': 1, 'shown': false, 'why': 'Breathing'},
        ],
      ),
    );

    expect(errors(), isEmpty);
  });

  test('names a catalogue exercise and known statuses', () {
    write('_kits.json', {
      ...kits,
      'rack': {'status': 'done'},
    });
    write('ex_missing.json', recipe());
    write('ex_a.json', recipe(status: 'done'));

    expect(errors(), [
      '_kits.json: kit rack has status done, not one of draft, approved',
      'ex_a.json: status done is not one of draft, review, approved, fix',
      'ex_missing.json: no catalogue exercise ex_missing',
    ]);
  });

  test('uses existing kits, only approved ones once approved', () {
    write('_kits.json', kits);
    write('ex_a.json', recipe(gear: ['barbell', 'bench', 'rings']));

    expect(errors(), [
      'ex_a.json: approved, but kit bench is not',
      'ex_a.json: gear names no kit rings',
    ]);

    write('ex_a.json', recipe(status: 'review', gear: ['bench']));
    expect(errors(), isEmpty);
  });

  test('keys name poses, start at 0 and end on the first pose', () {
    write('_kits.json', kits);
    write(
      'ex_a.json',
      recipe(
        keys: [
          [0.2, 'top'],
          [1, 'bottom'],
        ],
      ),
    );
    expect(errors(), [
      'ex_a.json: keys must start at 0',
      'ex_a.json: keys must end on the first pose, top',
    ]);

    write(
      'ex_a.json',
      recipe(
        keys: [
          [0, 'top'],
          [1, 'side'],
          ['x', 'top'],
        ],
      ),
    );
    expect(errors(), [
      'ex_a.json: keys: no pose side',
      'ex_a.json: keys: [x, top] is not [seconds, pose]',
    ]);
  });

  test('mistake lines are unique and within the exercise\'s mistakes', () {
    write('_kits.json', kits);
    write(
      'ex_a.json',
      recipe(
        mistakes: [
          {'line': 1, 'status': 'approved'},
          {'line': 1, 'shown': false},
          {'line': 2, 'status': 'approved'},
          {
            'line': 0,
            'status': 'approved',
            'keys': [
              [0, 'top'],
              [1, 'sag'],
              [2, 'top'],
            ],
          },
        ],
      ),
    );

    expect(errors(), [
      'ex_a.json: mistake line 1 appears twice',
      'ex_a.json: mistake line 2 is not one of the exercise\'s 2 mistakes',
      'ex_a.json: mistake line 0 keys: no pose sag',
    ]);
  });

  test('the kits file must exist', () {
    write('ex_a.json', recipe());

    expect(errors(), contains('_kits.json: missing'));
  });
}
