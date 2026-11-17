import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/sync_repository.dart';

/// Firestore's own queue: checked when listening starts and whenever the
/// app's listeners settle, which a write on this device or an answer from
/// the server causes. Writes the server takes within [settle] never show
/// as waiting.
class FirestoreSyncRepository implements SyncRepository {
  const FirestoreSyncRepository(
    this._firestore, {
    this.settle = const Duration(seconds: 2),
  });

  final FirebaseFirestore _firestore;
  final Duration settle;

  @override
  Stream<bool> watchBackedUp() {
    late final StreamController<bool> controller;
    StreamSubscription<void>? inSync;
    var check = 0;

    Future<void> recheck() async {
      final id = ++check;
      bool current() => id == check && !controller.isClosed;
      // Fails when the signed-in user changes; the next check follows.
      final written = _firestore.waitForPendingWrites().then(
        (_) => true,
        onError: (Object _) => false,
      );
      final sent = await written.timeout(settle, onTimeout: () => false);
      if (!current()) return;
      controller.add(sent);
      if (!sent && await written && current()) controller.add(true);
    }

    controller = StreamController<bool>(
      onListen: () {
        inSync = _firestore.snapshotsInSync().listen(
          (_) => unawaited(recheck()),
        );
        unawaited(recheck());
      },
      onCancel: () => inSync?.cancel(),
    );
    return controller.stream.distinct();
  }
}
