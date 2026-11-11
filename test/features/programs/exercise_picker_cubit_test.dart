import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_cubit.dart';

import 'fixtures.dart';

void main() {
  final a = move('a');
  final b = move('b');
  final c = move('c');

  group('picking several', () {
    blocTest<ExercisePickerCubit, ExercisePickerState>(
      'selects in order and deselects on a second tap',
      build: () => ExercisePickerCubit(max: 5, multiple: true),
      act: (cubit) => cubit
        ..toggle(b)
        ..toggle(a)
        ..toggle(b),
      expect: () => [
        ExercisePickerState(selected: [b]),
        ExercisePickerState(selected: [b, a]),
        ExercisePickerState(selected: [a]),
      ],
    );

    blocTest<ExercisePickerCubit, ExercisePickerState>(
      'stops at the maximum but still deselects',
      build: () => ExercisePickerCubit(max: 2, multiple: true),
      act: (cubit) {
        cubit
          ..toggle(a)
          ..toggle(b);
        expect(cubit.isFull, isTrue);
        cubit
          ..toggle(c)
          ..toggle(a)
          ..toggle(c);
      },
      expect: () => [
        ExercisePickerState(selected: [a]),
        ExercisePickerState(selected: [a, b]),
        ExercisePickerState(selected: [b]),
        ExercisePickerState(selected: [b, c]),
      ],
      verify: (cubit) {
        expect(cubit.state.isSelected(c), isTrue);
        expect(cubit.state.isSelected(a), isFalse);
        expect(cubit.state.done, isFalse);
      },
    );
  });

  blocTest<ExercisePickerCubit, ExercisePickerState>(
    'picking one finishes at the first tap',
    build: () => ExercisePickerCubit(max: 1, multiple: false),
    act: (cubit) => cubit
      ..toggle(b)
      ..toggle(a),
    expect: () => [
      ExercisePickerState(selected: [b], done: true),
    ],
  );
}
