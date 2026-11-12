import 'package:forge_core/forge_core.dart';

import 'body_entry.dart';

/// Completes once the server has a write: with null when it took it, with
/// the [Failure] when it refused it. Never completes while offline.
typedef Confirmation = Future<Failure?>;

abstract interface class BodyRepository {
  /// The most recent entries of user [uid], newest first, again on every
  /// change. Documents that cannot be read are skipped. Errors arrive as
  /// [Failure]s.
  Stream<List<BodyEntry>> watchEntries(String uid);

  /// Every entry of user [uid], as the server has them plus this device's
  /// writes not sent yet, once the server has answered; for housekeeping.
  Future<List<BodyEntry>> confirmedEntries(String uid);

  /// A new, unused entry id.
  String newEntryId(String uid);

  /// Stores a new entry under its id, leaving out what it does not have.
  ///
  /// The result only covers starting the write: Firestore applies it to the
  /// local cache, so the stream shows it at once, and sends it whenever the
  /// device is online. The [Confirmation] tells how the server took it; a
  /// refusal also arrives on [rejectedWrites].
  Future<Result<Confirmation>> addEntry(String uid, BodyEntry entry);

  /// Replaces the stored entry's date, weight, measurements and photos with
  /// [entry]'s, removing those it does not have; measurements and poses this
  /// app does not know are kept. Works like [addEntry].
  Future<Result<Confirmation>> updateEntry(String uid, BodyEntry entry);

  /// Works like [addEntry].
  Future<Result<Confirmation>> deleteEntry(String uid, String id);

  /// Writes the server refused after they had already reported success;
  /// their change has left the stream again.
  Stream<Failure> get rejectedWrites;
}
