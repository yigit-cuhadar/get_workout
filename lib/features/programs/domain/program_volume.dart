import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/muscle_volume.dart';
import '../../exercises/domain/vocabulary.dart';
import 'program.dart';

/// What a week of a program gives each muscle: every day once.
class ProgramVolume extends Equatable {
  const ProgramVolume({required this.sets, required this.total});

  /// Per muscle, counted as done workouts are (see [muscleSets]).
  final Map<Muscle, double> sets;

  /// The program's working sets, each once.
  final int total;

  @override
  List<Object?> get props => [sets, total];
}

/// [program]'s weekly volume, its exercises looked up in [exercises] by id;
/// an exercise no longer there still counts in [ProgramVolume.total] but
/// gives no muscle sets.
ProgramVolume programVolume(Program program, Map<String, Exercise> exercises) {
  final sets = <Muscle, double>{};
  var total = 0;
  for (final day in program.days) {
    for (final item in day.items) {
      total += item.sets;
      final exercise = exercises[item.exerciseId];
      if (exercise == null) continue;
      addMuscleSets(
        sets,
        muscleSets(
          main: exercise.mainMuscles,
          secondary: exercise.secondaryMuscles,
          sets: item.sets,
        ),
      );
    }
  }
  return ProgramVolume(sets: sets, total: total);
}
