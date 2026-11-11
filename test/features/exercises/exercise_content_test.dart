import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/data/exercise_map.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

/// The contract between `content/exercises/*.json` and the code: every
/// exercise reads into the entity and writes back to the same map, in the
/// shape Firestore stores it.
void main() {
  final files =
      Directory('content/exercises')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the content folder has exercise files', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    test(
      'every exercise in ${file.uri.pathSegments.last} parses losslessly',
      () {
        final entries = (jsonDecode(file.readAsStringSync()) as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(entries, isNotEmpty);
        for (final entry in entries) {
          final id = entry['id']! as String;
          final exercise = exerciseFromMap(id, entry);
          expect(exercise.id, id);
          expect(exerciseToMap(exercise), _firestoreShape(entry), reason: id);
        }
      },
    );
  }

  test('ids are unique across all files', () {
    final ids = [
      for (final file in files)
        for (final entry
            in jsonDecode(file.readAsStringSync()) as List<Object?>)
          (entry! as Map<String, Object?>)['id'],
    ];
    expect(ids.toSet(), hasLength(ids.length));
  });

  group('vocabulary', () {
    final lists = <String, List<Coded>>{
      'status': ExerciseStatus.values,
      'loggingType': LoggingType.values,
      'muscle': Muscle.values,
      'equipment': Equipment.values,
      'movementPattern': MovementPattern.values,
      'mechanic': Mechanic.values,
      'laterality': Laterality.values,
      'level': Level.values,
      'force': Force.values,
      'position': Position.values,
      'grip': Grip.values,
      'gripWidth': GripWidth.values,
    };

    test('has the sizes SPEC.md lists', () {
      expect(lists.map((name, values) => MapEntry(name, values.length)), {
        'status': 3,
        'loggingType': 6,
        'muscle': 19,
        'equipment': 25,
        'movementPattern': 14,
        'mechanic': 2,
        'laterality': 3,
        'level': 3,
        'force': 3,
        'position': 12,
        'grip': 4,
        'gripWidth': 3,
      });
    });

    for (final MapEntry(key: name, value: values) in lists.entries) {
      test('$name codes are unique and round-trip', () {
        expect(values.map((v) => v.code).toSet(), hasLength(values.length));
        for (final value in values) {
          expect(values.byCode(value.code), same(value));
        }
        expect(values.byCode('nope'), isNull);
        expect(values.byCode(null), isNull);
      });
    }
  });
}

/// [entry] as stored in Firestore: the id is the document id, and each
/// equipment alternative is an `{items: [...]}` map.
Map<String, Object?> _firestoreShape(Map<String, Object?> entry) => {
  ...entry,
  if (entry['equipmentAlternatives'] case final List<Object?> alternatives)
    'equipmentAlternatives': [
      for (final set in alternatives) {'items': set},
    ],
}..remove('id');
