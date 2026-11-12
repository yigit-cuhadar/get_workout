import 'package:forge_core/forge_core.dart';

import 'body_entry.dart';

abstract interface class BodyRepository {
  /// The most recent entries of user [uid], newest first, again on every
  /// change. Documents that cannot be read are skipped. Errors arrive as
  /// [Failure]s.
  Stream<List<BodyEntry>> watchEntries(String uid);

  /// A new, unused entry id.
  String newEntryId(String uid);

  /// Stores a new entry under its id, leaving out what it does not have.
  ///
  /// The result only covers starting the write: Firestore applies it to the
  /// local cache, so the stream shows it at once, and sends it whenever the
  /// device is online. A rejection after that arrives on [rejectedWrites].
  Future<Result<void>> addEntry(String uid, BodyEntry entry);

  /// Replaces the stored entry's date, weight, measurements and photos with
  /// [entry]'s, removing those it does not have; measurements and poses this
  /// app does not know are kept. Works like [addEntry].
  Future<Result<void>> updateEntry(String uid, BodyEntry entry);

  /// Works like [addEntry].
  Future<Result<void>> deleteEntry(String uid, String id);

  /// Writes the server refused after they had already reported success;
  /// their change has left the stream again.
  Stream<Failure> get rejectedWrites;
}
