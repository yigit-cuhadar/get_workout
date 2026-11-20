import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/admin_feedback_repository.dart';
import '../domain/feedback_entry.dart';

/// Reads every user's `feedback` subcollection as one collection group,
/// through the index on `status` and `createdAt` (firestore.indexes.json).
class FirestoreAdminFeedbackRepository implements AdminFeedbackRepository {
  const FirestoreAdminFeedbackRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// How many messages of a status the page shows.
  static const pageSize = 100;

  @override
  Stream<List<FeedbackEntry>> watch(FeedbackEntryStatus status) => _firestore
      .collectionGroup('feedback')
      .where('status', isEqualTo: status.name)
      .orderBy('createdAt', descending: true)
      .limit(pageSize)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            fromMap(doc.reference.path, doc.data()),
        ],
      )
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('admin', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );

  @override
  Future<Result<void>> setStatus(String path, FeedbackEntryStatus status) =>
      guard(
        () => _firestore.doc(path).update({'status': status.name}),
        mapper: mapFirebaseError,
      );

  static FeedbackEntry fromMap(String path, Map<String, Object?> data) {
    String text(String field) => switch (data[field]) {
      final String value => value,
      _ => '',
    };
    return FeedbackEntry(
      path: path,
      uid: text('uid'),
      email: data['email'] is String ? data['email']! as String : null,
      message: text('message'),
      source: text('source'),
      appVersion: text('appVersion'),
      platform: text('platform'),
      osVersion: text('osVersion'),
      deviceModel: text('deviceModel'),
      locale: text('locale'),
      createdAt: switch (data['createdAt']) {
        final Timestamp at => at.toDate(),
        _ => null,
      },
      status: data['status'] == FeedbackEntryStatus.closed.name
          ? FeedbackEntryStatus.closed
          : FeedbackEntryStatus.open,
    );
  }
}
