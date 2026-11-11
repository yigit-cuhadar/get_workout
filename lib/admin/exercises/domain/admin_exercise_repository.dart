import 'package:forge_core/forge_core.dart';

import 'exercise_draft.dart';

/// `exercises/{id}` of every status, edited in place. Writes need the admin
/// claim; without it they fail with a [PermissionFailure].
abstract interface class AdminExerciseRepository {
  /// Every document, again whenever one changes. Errors are [Failure]s.
  Stream<List<ExerciseRecord>> watchAll();

  /// The document as the server holds it now; [NotFoundFailure] when absent.
  Future<Result<ExerciseRecord>> load(String id);

  /// Writes a new document, unless the id is taken ([IdTaken]). A save that
  /// was written is always [Saved], even when reading it back failed.
  Future<Result<SaveOutcome>> create(ExerciseDraft draft);

  /// Replaces the managed fields of an existing document, unless its
  /// `updatedAt` is no longer [loadedUpdatedAt] ([ChangedSinceLoaded]).
  /// `contentHash` and unknown fields are kept; `updatedAt` becomes the
  /// server time.
  Future<Result<SaveOutcome>> update(
    ExerciseDraft draft, {
    required DateTime? loadedUpdatedAt,
  });
}
