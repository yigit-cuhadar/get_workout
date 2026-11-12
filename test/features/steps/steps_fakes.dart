import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/steps/domain/steps_prompt.dart';

/// The asked-here marker in memory; [failure] fails every call.
class MemoryStepsPrompt implements StepsPrompt {
  bool asked = false;
  Failure? failure;

  @override
  Future<Result<bool>> askedHere() async =>
      failure == null ? Ok(asked) : Err(failure!);

  @override
  Future<Result<void>> markAskedHere() async {
    if (failure case final failure?) return Err(failure);
    asked = true;
    return const Ok(null);
  }
}
