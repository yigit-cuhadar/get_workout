import 'package:forge_core/forge_core.dart';

import 'active_program.dart';
import 'program.dart';

/// User programs (`users/{uid}/programs`) and the active program
/// (`users/{uid}.activeProgram`), together because deleting the active
/// program also stops it, in one write.
///
/// Writes only start: Firestore applies them to its local cache at once, so
/// streams show them immediately, and sends them whenever the device is
/// online. A write the server refuses later arrives on [rejectedWrites].
/// Stream errors arrive as [Failure]s.
abstract interface class ProgramRepository {
  /// User [uid]'s programs by name, again on every change. Documents that
  /// cannot be read are skipped.
  Stream<List<Program>> watchPrograms(String uid);

  /// One program; a [NotFoundFailure] when there is none or it cannot be
  /// read.
  Future<Result<Program>> getProgram(String uid, String id);

  /// Stores [program] as a new one, returning its new id.
  Future<Result<String>> createProgram(String uid, Program program);

  /// Replaces the name, length and days of the stored [program]; anything
  /// else on the document is kept.
  Future<Result<void>> updateProgram(String uid, Program program);

  /// Deletes program [id], and with [clearActive] also stops it.
  Future<Result<void>> deleteProgram(
    String uid,
    String id, {
    required bool clearActive,
  });

  /// Null when there is none or it cannot be read.
  Stream<ActiveProgram?> watchActiveProgram(String uid);

  /// Replaces the active program, whatever it was, with [active]. Nothing
  /// else of `users/{uid}` is touched by this or the writes below.
  Future<Result<void>> startProgram(String uid, ActiveProgram active);

  /// Changes the active program to [active], keeping its fields this app
  /// version does not know.
  Future<Result<void>> updateActiveProgram(String uid, ActiveProgram active);

  Future<Result<void>> stopProgram(String uid);

  Stream<Failure> get rejectedWrites;
}
