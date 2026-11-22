import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_editing.dart';

void main() {
  // The server's generator rebuilds estimateDay (`estimateDayS` in
  // functions/src/generator/engine.ts); both are held to these vectors.
  test('estimateDay gives the shared vectors', () {
    final vectors = jsonDecode(
      File('test/fixtures/estimate_vectors.json').readAsStringSync(),
    ) as List;
    expect(vectors, isNotEmpty);
    for (final vector in vectors) {
      final items = [
        for (final item
            in ((vector as Map)['items'] as List).cast<Map<String, Object?>>())
          ProgramItem(
            exerciseId: item['exerciseId']! as String,
            sets: item['sets']! as int,
            repMin: item['repMin'] as int?,
            repMax: item['repMax'] as int?,
            durationS: item['durationS'] as int?,
            restS: item['restS']! as int,
            group: item['group'] as String?,
          ),
      ];
      expect(
        estimateDay(ProgramDay(items: items)).inSeconds,
        vector['seconds'],
        reason: jsonEncode(vector['items']),
      );
    }
  });
}
