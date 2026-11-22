import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';

/// A program the server generated, as the preview edits it.
class GeneratedProgram extends Equatable {
  const GeneratedProgram({
    required this.splitName,
    required this.lengthWeeks,
    required this.days,
    this.uncovered = const {},
  });

  /// In the language the program was asked for.
  final String splitName;
  final int lengthWeeks;

  /// Named by the server ("Upper A").
  final List<ProgramDay> days;

  /// Muscles with a weekly target that no exercise of the week, as
  /// generated, works as a main muscle.
  final Set<Muscle> uncovered;

  GeneratedProgram withDays(List<ProgramDay> days) => GeneratedProgram(
    splitName: splitName,
    lengthWeeks: lengthWeeks,
    days: days,
    uncovered: uncovered,
  );

  /// The [uncovered] muscles that still no exercise of [days] works as a
  /// main muscle, the exercises looked up in [exercises].
  Set<Muscle> stillUncovered(Map<String, Exercise> exercises) {
    final trained = {
      for (final day in days)
        for (final item in day.items)
          ...?exercises[item.exerciseId]?.mainMuscles,
    };
    return uncovered.difference(trained);
  }

  /// The program to store: the user's own, editable like any other.
  Program toProgram({required String name}) => Program(
    name: name,
    origin: ProgramOrigin.generated,
    lengthWeeks: lengthWeeks,
    days: days,
  );

  @override
  List<Object?> get props => [splitName, lengthWeeks, days, uncovered];
}
