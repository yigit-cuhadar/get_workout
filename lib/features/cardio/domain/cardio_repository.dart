import 'package:forge_core/forge_core.dart';

import 'cardio_session.dart';

abstract interface class CardioRepository {
  /// The most recent sessions of user [uid], newest first, again on every
  /// change. Documents that cannot be read are skipped. Errors arrive as
  /// [Failure]s.
  Stream<List<CardioSession>> watchSessions(String uid);

  /// Creates the session, with all its values, when it has no id. Otherwise
  /// updates the stored one in place: the type, date and duration, plus the
  /// optional [fields] (removing those that are null); anything else on the
  /// document is kept.
  ///
  /// The result only covers starting the write: Firestore applies it to the
  /// local cache, so the stream shows it at once, and sends it whenever the
  /// device is online. A rejection after that arrives on [rejectedWrites].
  Future<Result<void>> saveSession(
    String uid,
    CardioSession session, {
    required Set<CardioField> fields,
  });

  /// Works like [saveSession].
  Future<Result<void>> deleteSession(String uid, String id);

  /// Writes the server refused after [saveSession] or [deleteSession] had
  /// already reported success; their change has left the stream again.
  Stream<Failure> get rejectedWrites;
}
