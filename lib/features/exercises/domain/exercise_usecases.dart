import 'package:forge_core/forge_core.dart';

import 'custom_exercise.dart';
import 'custom_exercise_repository.dart';
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

typedef CustomExerciseSave = ({String uid, CustomExercise exercise});

typedef CustomExerciseDelete = ({String uid, String id});

/// The user's custom exercises as [Exercise]s, ready to merge into the
/// catalogue.
class WatchCustomExercises {
  const WatchCustomExercises(this._repository);
  final CustomExerciseRepository _repository;

  Stream<List<Exercise>> call(String uid) => _repository
      .watchCustomExercises(uid)
      .map(
        (exercises) => [
          for (final exercise in exercises) exercise.toExercise(),
        ],
      );
}

class WatchRejectedCustomExerciseWrites {
  const WatchRejectedCustomExerciseWrites(this._repository);
  final CustomExerciseRepository _repository;

  Stream<Failure> call() => _repository.rejectedWrites;
}

/// Creates the exercise when it has no id, otherwise updates it. Trims the
/// name and drops a blank note first. An invalid exercise is refused with a
/// [ValidationFailure] naming its issues; a new one beyond
/// [CustomExerciseLimits.maxCount] with [CustomExerciseLimits.limitReached].
class SaveCustomExercise implements UseCase<void, CustomExerciseSave> {
  const SaveCustomExercise(this._repository);
  final CustomExerciseRepository _repository;

  @override
  Future<Result<void>> call(CustomExerciseSave params) async {
    final given = params.exercise;
    final note = given.note?.trim() ?? '';
    final exercise = CustomExercise(
      id: given.id,
      name: given.name.trim(),
      loggingType: given.loggingType,
      mainMuscles: given.mainMuscles,
      secondaryMuscles: given.secondaryMuscles,
      equipment: given.equipment,
      note: note.isEmpty ? null : note,
    );
    final issues = validateCustomExercise(exercise);
    if (issues.isNotEmpty) {
      return Err(ValidationFailure(issues.map((i) => i.name).join(', ')));
    }
    if (exercise.id != null) {
      return _repository.updateCustomExercise(params.uid, exercise);
    }
    final count = await _repository.countCustomExercises(params.uid);
    return switch (count) {
      Err(:final failure) => Err(failure),
      Ok(value: final count) when count >= CustomExerciseLimits.maxCount =>
        const Err(CustomExerciseLimits.limitReached),
      Ok() => _repository.createCustomExercise(params.uid, exercise),
    };
  }
}

/// Also removes it from the favourites. Programs and workouts that name it
/// then find no exercise with its id, as with a retired one.
class DeleteCustomExercise implements UseCase<void, CustomExerciseDelete> {
  const DeleteCustomExercise(this._repository);
  final CustomExerciseRepository _repository;

  @override
  Future<Result<void>> call(CustomExerciseDelete params) =>
      _repository.deleteCustomExercise(params.uid, params.id);
}
