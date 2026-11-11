import 'package:forge_core/forge_core.dart';

import 'exercise.dart';
import 'exercise_repository.dart';
import 'user_library_repository.dart';
import 'vocabulary.dart';

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

typedef EquipmentUpdate = ({String uid, Set<Equipment> equipment});

typedef FavoriteUpdate = ({String uid, String exerciseId, bool favorite});

class WatchOwnedEquipment {
  const WatchOwnedEquipment(this._repository);
  final UserLibraryRepository _repository;

  Stream<Set<Equipment>?> call(String uid) => _repository.watchEquipment(uid);
}

/// Bodyweight is always owned, so it is never stored.
class SaveOwnedEquipment implements UseCase<void, EquipmentUpdate> {
  const SaveOwnedEquipment(this._repository);
  final UserLibraryRepository _repository;

  @override
  Future<Result<void>> call(EquipmentUpdate params) =>
      _repository.saveEquipment(
        params.uid,
        {...params.equipment}..remove(Equipment.bodyweight),
      );
}

class WatchFavorites {
  const WatchFavorites(this._repository);
  final UserLibraryRepository _repository;

  Stream<Set<String>> call(String uid) => _repository.watchFavorites(uid);
}

class SetFavorite implements UseCase<void, FavoriteUpdate> {
  const SetFavorite(this._repository);
  final UserLibraryRepository _repository;

  @override
  Future<Result<void>> call(FavoriteUpdate params) => _repository.setFavorite(
    params.uid,
    params.exerciseId,
    favorite: params.favorite,
  );
}
