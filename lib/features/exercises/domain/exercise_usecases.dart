import 'package:forge_core/forge_core.dart';

import 'exercise.dart';
import 'exercise_repository.dart';

class WatchExercises {
  const WatchExercises(this._repository);
  final ExerciseRepository _repository;

  Stream<List<Exercise>> call() => _repository.watchExercises();
}

class SyncExercises implements UseCase<void, NoParams> {
  const SyncExercises(this._repository);
  final ExerciseRepository _repository;

  @override
  Future<Result<void>> call([NoParams params = const NoParams()]) =>
      _repository.sync();
}
