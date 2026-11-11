import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';

class ExercisePickerState extends Equatable {
  const ExercisePickerState({this.selected = const [], this.done = false});

  /// In the order they were picked.
  final List<Exercise> selected;

  /// A single pick was made; the picker returns [selected].
  final bool done;

  bool isSelected(Exercise exercise) =>
      selected.any((other) => other.id == exercise.id);

  @override
  List<Object?> get props => [selected, done];
}

/// Picking exercises from the library list: up to [max] of them, or with
/// [multiple] off exactly one, which finishes the pick at once.
class ExercisePickerCubit extends Cubit<ExercisePickerState> {
  ExercisePickerCubit({required this.max, required this.multiple})
    : assert(max >= 1),
      super(const ExercisePickerState());

  final int max;
  final bool multiple;

  bool get isFull => state.selected.length >= max;

  /// Selects [exercise], or deselects it when it is selected. Beyond [max]
  /// nothing more is selected.
  void toggle(Exercise exercise) {
    if (state.done) return;
    if (!multiple) {
      emit(ExercisePickerState(selected: [exercise], done: true));
      return;
    }
    if (state.isSelected(exercise)) {
      emit(
        ExercisePickerState(
          selected: [
            for (final other in state.selected)
              if (other.id != exercise.id) other,
          ],
        ),
      );
    } else if (!isFull) {
      emit(ExercisePickerState(selected: [...state.selected, exercise]));
    }
  }
}
