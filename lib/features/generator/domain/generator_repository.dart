import 'package:forge_core/forge_core.dart';

import '../../programs/domain/program.dart';
import 'generated_program.dart';
import 'generator_answers.dart';
import 'generator_options.dart';

/// What the server is asked for: a program for [answers]; [seed] varies
/// it, [kept] holds per day the items Regenerate keeps, and [language] is
/// the one its names come in.
typedef GenerationRequest = ({
  GeneratorAnswers answers,
  int seed,
  List<List<ProgramItem>> kept,
  String language,
});

/// Why the server made no program.
enum GenerationRefusal {
  /// The server does not see Premium yet, e.g. while a purchase reaches it.
  notPremium,

  /// No rules were ever published.
  noRules,

  /// No template fits the days, level and goal.
  noTemplate,

  /// The answers leave a day without an exercise.
  noExercises,

  /// The request broke the server's checks: a bug in the app.
  invalidInput,
}

final class GenerationRefused extends Failure {
  const GenerationRefused(this.refusal, super.message, {super.cause});

  final GenerationRefusal refusal;
}

abstract interface class GeneratorRepository {
  Future<Result<GeneratedProgram>> generate(GenerationRequest request);

  /// What the questions offer; errors with a [Failure]: a
  /// [NotFoundFailure] while nothing is published.
  Stream<GeneratorOptions> watchOptions();
}
