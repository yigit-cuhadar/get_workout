import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import '../../tool/src/content_validator.dart';
import '../../tool/src/content_import.dart';
import 'fixtures.dart';

void main() {
  test('every content file exercise survives the editor unchanged', () {
    // So saving an exercise without changes writes what the import wrote,
    // and its contentHash still matches.
    final report = validateContent(Directory('content/exercises'));
    expect(report.exercises, isNotEmpty);
    for (final entry in report.exercises) {
      final json = ExerciseDraft.fromJson(entry.data).toJson();
      expect(json, entry.data, reason: entry.id);
      expect(
        contentHash(exerciseContent(json)),
        contentHash(exerciseContent(entry.data)),
        reason: entry.id,
      );
    }
  });

  test('unknown codes and wrong types read as unset', () {
    final draft = ExerciseDraft.fromJson({
      ...validJson(),
      'loggingType': 'juggling',
      'familyRank': '1',
      'equipment': ['dumbbell', 'laser'],
    });
    expect(draft.loggingType, isNull);
    expect(draft.familyRank, isNull);
    expect(draft.equipment, [Equipment.dumbbell]);
  });

  test('copyWith clears optional fields with null and keeps the rest', () {
    final draft = ExerciseDraft.fromJson(validJson());
    final cleared = draft.copyWith(grip: null, incrementKg: null);
    expect(cleared.grip, isNull);
    expect(cleared.incrementKg, isNull);
    expect(cleared.copyWith(), cleared);
    expect(cleared.loggingType, LoggingType.weightReps);
  });

  test('optional text and empty alternatives are left out', () {
    final json = const ExerciseDraft(safety: '').toJson();
    expect(json.containsKey('equipmentAlternatives'), isFalse);
    expect(json.containsKey('grip'), isFalse);
    expect(json.containsKey('incrementKg'), isFalse);
    expect((json['l10n']! as Map)['en'], isNot(contains('safety')));
  });

  test('a whole increment stored as an integer reads as a double', () {
    // What a web client writes for 2.0.
    final draft = ExerciseDraft.fromJson({...validJson(), 'incrementKg': 2});
    expect(draft.incrementKg, 2.0);
    expect(draft.incrementKg, isA<double>());
  });
}
