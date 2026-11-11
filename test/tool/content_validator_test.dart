import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';

import '../../tool/src/content_validator.dart';

void main() {
  test('reports the same errors as the standalone validator did', () {
    // broken_errors.txt is the stderr of the validator before it became a
    // library, run on the same fixture, with the coverage lines of the
    // equipment profiles updated when they became EquipmentProfile.
    final expected = File('test/tool/fixtures/broken_errors.txt')
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();

    final report = validateContent(Directory('test/tool/fixtures/broken'));

    expect(report.errors, expected);
    expect(report.perFile, {'exercises.json': 3});
    expect(report.exercises.map((e) => e.id), [
      'ex_dumbbell_curl',
      'ex_Bad',
      'ex_dumbbell_curl',
    ]);
  });

  test('every program file passes validation against the real exercises', () {
    final report = validateContent(
      Directory('content/exercises'),
      programs: Directory('content/programs'),
    );

    expect(report.errors, isEmpty);
    expect(report.programs, hasLength(25));
    final live = report.programs.where((p) => p.isLive);
    expect(live.where((p) => p.isPremium), hasLength(19));
    expect(live.where((p) => !p.isPremium), hasLength(6));
  });

  test('every program file passes the app\'s validateProgram', () {
    final report = validateContent(
      Directory('content/exercises'),
      programs: Directory('content/programs'),
    );
    final loggingTypes = liveLoggingTypes(report.library);

    expect(report.programs, hasLength(25));
    for (final p in report.programs) {
      final result = validateProgram(p.program, loggingTypes);
      expect(result.isValid, isTrue, reason: '${p.id}: $result');
    }
  });

  group('program files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('programs'));
    tearDown(() => dir.deleteSync(recursive: true));

    List<String> errors() => validateContent(
      Directory('test/tool/fixtures/broken'),
      programs: dir,
    ).errors.where((e) => e.startsWith('pr_')).toList();

    test('are one JSON object each, named after the id', () {
      File('${dir.path}/pr_list.json').writeAsStringSync('[]');
      File('${dir.path}/pr_other.json').writeAsStringSync('{"id": "pr_a"}');
      File('${dir.path}/pr_bad.json').writeAsStringSync('{');

      final found = errors();
      expect(found, contains(startsWith('pr_bad.json: invalid JSON')));
      expect(found, contains('pr_list.json: top level must be a JSON object'));
      expect(
        found,
        contains('pr_other.json [pr_a]: file must be named pr_a.json'),
      );
      // The rules run on a misnamed file too.
      expect(
        found,
        contains('pr_other.json [pr_a]: premium must be true or false'),
      );
    });
  });
}
