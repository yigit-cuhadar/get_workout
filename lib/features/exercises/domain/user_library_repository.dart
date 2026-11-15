import 'package:forge_core/forge_core.dart';

import 'vocabulary.dart';

/// What a user keeps about the library: the equipment they own, their
/// favourite exercises and their own notes on exercises. Streams emit the current value, then every change;
/// errors arrive as [Failure]s.
abstract interface class UserLibraryRepository {
  /// The equipment user [uid] owns, never including
  /// [Equipment.bodyweight]; null until they have chosen.
  Stream<Set<Equipment>?> watchEquipment(String uid);

  /// Stores [equipment] without touching anything else of the user.
  Future<Result<void>> saveEquipment(String uid, Set<Equipment> equipment);

  /// The ids of user [uid]'s favourite exercises; empty when there are none.
  Stream<Set<String>> watchFavorites(String uid);

  /// Adds or removes one favourite without touching the others.
  Future<Result<void>> setFavorite(
    String uid,
    String exerciseId, {
    required bool favorite,
  });

  /// User [uid]'s own notes on exercises by exercise id; empty when there
  /// are none.
  Stream<Map<String, String>> watchExerciseNotes(String uid);

  /// Stores [note] on [exerciseId] without touching the other notes; an
  /// empty [note] removes it.
  Future<Result<void>> setExerciseNote(
    String uid,
    String exerciseId,
    String note,
  );
}
