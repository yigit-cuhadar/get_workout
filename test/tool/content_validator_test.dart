import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
