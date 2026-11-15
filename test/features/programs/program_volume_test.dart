import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/program_volume.dart';

import '../exercises/fixtures.dart';
import 'fixtures.dart';

void main() {
  test('counts every day once, main muscles fully and secondary by half', () {
    // Items a to d have 3 sets each.
    final volume = programVolume(program(id: 'p1'), {
      'a': exercise('a', main: [Muscle.pec], secondary: [Muscle.triceps]),
      'b': exercise('b', main: [Muscle.pec]),
      'c': exercise('c', main: [Muscle.quads], secondary: [Muscle.glute]),
      'd': exercise('d', main: [Muscle.hamstring]),
    });
    expect(volume.total, 12);
    expect(volume.sets, {
      Muscle.pec: 6,
      Muscle.triceps: 1.5,
      Muscle.quads: 3,
      Muscle.glute: 1.5,
      Muscle.hamstring: 3,
    });
  });

  test('an exercise no longer in the library counts in the total only', () {
    final volume = programVolume(program(id: 'p1'), {
      'a': exercise('a', main: [Muscle.pec]),
    });
    expect(volume.total, 12);
    expect(volume.sets, {Muscle.pec: 3});
  });
}
