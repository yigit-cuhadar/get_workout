import 'package:forge_core/forge_core.dart';

import 'program_draft.dart';

/// The ready-made programs, `programs/{id}` (the card) and
/// `programs/{id}/detail/main` (the days), of every status, edited in
/// place. Writes need the admin claim; without it they fail with a
/// [PermissionFailure].
abstract interface class AdminProgramRepository {
  /// Every card, again whenever one changes; the days are not read. Errors
  /// are [Failure]s.
  Stream<List<ProgramRecord>> watchCards();

  /// The card and its days as the server holds them now; [NotFoundFailure]
  /// when there is no card.
  Future<Result<ProgramRecord>> load(String id);

  /// Writes a new program from [content] (the content-file shape), card and
  /// detail in one commit, unless the id is taken ([ProgramIdTaken]). A
  /// save that was written is always [ProgramSaved], even when reading it
  /// back failed.
  Future<Result<ProgramSaveOutcome>> create(Map<String, Object?> content);

  /// Replaces the managed fields of an existing program's card and detail in
  /// one commit, unless either changed since [loaded]
  /// ([ProgramChangedSinceLoaded]). `contentHash` and unknown fields are
  /// kept; both `updatedAt` become the server time.
  Future<Result<ProgramSaveOutcome>> update(
    Map<String, Object?> content, {
    required ProgramVersion loaded,
  });
}
