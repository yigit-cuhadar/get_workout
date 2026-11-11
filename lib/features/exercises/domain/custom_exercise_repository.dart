import 'package:forge_core/forge_core.dart';

import 'custom_exercise.dart';

/// A user's own exercises (`users/{uid}/customExercises`).
///
/// Writes only start: Firestore applies them to its local cache at once, so
/// the stream shows them immediately, and sends them whenever the device is
/// online. A write the server refuses later arrives on [rejectedWrites].
/// Stream errors arrive as [Failure]s.
abstract interface class CustomExerciseRepository {
  /// User [uid]'s custom exercises, each with its id, again on every
  /// change. Documents that cannot be read are skipped.
  Stream<List<CustomExercise>> watchCustomExercises(String uid);

  /// How many custom exercises user [uid] has, as the first value of
  /// [watchCustomExercises] would know it, so it also works offline. The
  /// catalogue follows that stream while a user is signed in, which keeps
  /// the count current.
  Future<Result<int>> countCustomExercises(String uid);

  /// Stores [exercise], which has no id, as a new one.
  Future<Result<void>> createCustomExercise(
    String uid,
    CustomExercise exercise,
  );

  /// Replaces the stored [exercise]'s fields; it has an id.
  Future<Result<void>> updateCustomExercise(
    String uid,
    CustomExercise exercise,
  );

  /// Deletes custom exercise [id] and, in the same write, removes it from
  /// the user's favourites.
  Future<Result<void>> deleteCustomExercise(String uid, String id);

  Stream<Failure> get rejectedWrites;
}
