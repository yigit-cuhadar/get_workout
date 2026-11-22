import 'package:forge_core/forge_core.dart';

import 'generated_program.dart';
import 'generator_options.dart';
import 'generator_repository.dart';

/// A program from the server, or a [GenerationRefused] or another failure
/// saying why there is none.
class GenerateProgram implements UseCase<GeneratedProgram, GenerationRequest> {
  const GenerateProgram(this._repository);
  final GeneratorRepository _repository;

  @override
  Future<Result<GeneratedProgram>> call(GenerationRequest params) =>
      _repository.generate(params);
}

class WatchGeneratorOptions {
  const WatchGeneratorOptions(this._repository);
  final GeneratorRepository _repository;

  Stream<GeneratorOptions> call() => _repository.watchOptions();
}
