import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../programs/domain/program.dart';
import 'generator_answers.dart';
import 'program_generator.dart';

/// [exercises] is the library to choose from; [seed] and [kept] see
/// [generateProgram].
typedef GenerationRequest = ({
  GeneratorAnswers answers,
  List<Exercise> exercises,
  int seed,
  List<List<ProgramItem>> kept,
});

/// A program from the answers, or a [GenerationFailure] saying why none
/// can be made; see [generateProgram].
class GenerateProgram implements UseCase<GeneratedProgram, GenerationRequest> {
  const GenerateProgram();

  @override
  Future<Result<GeneratedProgram>> call(GenerationRequest params) async =>
      generateProgram(
        params.answers,
        params.exercises,
        seed: params.seed,
        kept: params.kept,
      );
}
