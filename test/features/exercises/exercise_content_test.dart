import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/data/exercise_map.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

/// The contract between `content/exercises/*.json` and the code: every
/// exercise reads into the entity with nothing lost, which [_storedForm]
/// proves by rebuilding the source map from the entity.
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
          expect(_statuses, contains(entry['status']), reason: id);
          expect(
            _storedForm(exercise),
            {...entry}..removeWhere((key, _) => key == 'id' || key == 'status'),
            reason: id,
          );
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

/// Read by the sync, not the entity.
const _statuses = {'draft', 'live', 'retired'};

/// [exercise] in the shape of a content file entry, without `id` and
/// `status`. Optional fields that are unset are left out.
Map<String, Object?> _storedForm(Exercise exercise) {
  List<String> codes(List<Coded> values) => [for (final v in values) v.code];
  return {
    'loggingType': exercise.loggingType.code,
    'mechanic': exercise.mechanic.code,
    'laterality': exercise.laterality.code,
    'level': exercise.level.code,
    'force': exercise.force.code,
    'movementPattern': exercise.movementPattern.code,
    'position': exercise.position.code,
    'grip': ?exercise.grip?.code,
    'gripWidth': ?exercise.gripWidth?.code,
    'equipment': codes(exercise.equipment),
    if (exercise.equipmentAlternatives.isNotEmpty)
      'equipmentAlternatives': [
        for (final set in exercise.equipmentAlternatives) codes(set),
      ],
    'mainMuscles': codes(exercise.mainMuscles),
    'secondaryMuscles': codes(exercise.secondaryMuscles),
    'family': exercise.family,
    'familyRank': exercise.familyRank,
    'pinnedAlternatives': exercise.pinnedAlternatives,
    'excludedAlternatives': exercise.excludedAlternatives,
    'defaultRestS': exercise.defaultRestS,
    'incrementKg': ?exercise.incrementKg,
    'popularity': exercise.popularity,
    'l10n': {
      for (final MapEntry(key: language, value: text) in exercise.l10n.entries)
        language: {
          'name': text.name,
          'aliases': text.aliases,
          'setup': text.setup,
          'execution': text.execution,
          'mistakes': text.mistakes,
          'safety': ?text.safety,
          'cues': text.cues,
        },
    },
  };
}
