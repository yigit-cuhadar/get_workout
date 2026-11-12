import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/muscle_volume.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

void main() {
  test('a set counts 1 for each main and 0.5 for each secondary muscle', () {
    expect(
      muscleSets(
        main: [Muscle.pec],
        secondary: [Muscle.triceps, Muscle.frontDelt],
        sets: 3,
      ),
      {Muscle.pec: 3.0, Muscle.triceps: 1.5, Muscle.frontDelt: 1.5},
    );
  });

  test('no sets give every muscle none', () {
    expect(
      muscleSets(main: [Muscle.lat], secondary: [Muscle.biceps], sets: 0),
      {Muscle.lat: 0.0, Muscle.biceps: 0.0},
    );
  });

  test('adds muscle by muscle', () {
    final total = {Muscle.pec: 2.0};
    addMuscleSets(total, {Muscle.pec: 1.5, Muscle.lat: 1.0});
    expect(total, {Muscle.pec: 3.5, Muscle.lat: 1.0});
  });
}
