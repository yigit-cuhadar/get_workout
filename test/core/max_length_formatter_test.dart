import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/max_length_formatter.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

void main() {
  String typed(String text, int max) => maxLengthFormatter(max)
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
      .text;

  test('cuts to code units, never half a surrogate pair', () {
    expect(typed('abc', 5), 'abc');
    expect(typed('a💪b', 2), 'a');
    expect(typed('a💪b', 3), 'a💪');
  });

  test('a custom exercise name or note it accepts always validates', () {
    final name = typed(
      '💪' * CustomExerciseLimits.maxNameLength,
      CustomExerciseLimits.maxNameLength,
    );
    final note = typed(
      '💪' * CustomExerciseLimits.maxNoteLength,
      CustomExerciseLimits.maxNoteLength,
    );
    expect(
      validateCustomExercise(
        CustomExercise(name: name, mainMuscles: const [Muscle.pec], note: note),
      ),
      isEmpty,
    );
  });
}
