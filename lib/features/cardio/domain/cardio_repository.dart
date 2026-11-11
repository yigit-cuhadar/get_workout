import 'package:forge_core/forge_core.dart';

import 'cardio_session.dart';

abstract interface class CardioRepository {
  /// All sessions of user [uid], newest first, again on every change. Errors
  /// arrive as [Failure]s.
  Stream<List<CardioSession>> watchSessions(String uid);

  /// Creates the session when it has no id, otherwise replaces it.
  ///
  /// Completes once the write is in the local cache, which shows it at once;
  /// it reaches the server whenever the device is online. A later rejection
  /// by the server is logged and the change disappears from the stream.
  Future<Result<void>> saveSession(String uid, CardioSession session);

  /// Completes like [saveSession].
  Future<Result<void>> deleteSession(String uid, String id);
}
