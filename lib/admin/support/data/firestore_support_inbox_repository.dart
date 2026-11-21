import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/support_inbox_repository.dart';
import '../domain/support_thread.dart';

/// Reads every user's `feedback` subcollection as one collection group,
/// through the index on `status` and `createdAt` (firestore.indexes.json),
/// and each thread's `replies`; replies go through the callable
/// `sendSupportReply` (`functions/src/send_support_reply.ts`).
class FirestoreSupportInboxRepository implements SupportInboxRepository {
  const FirestoreSupportInboxRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  static const function = 'sendSupportReply';

  /// How many threads of a list the inbox shows.
  static const pageSize = 100;

  /// `details.reason` values of the function's refusals.
  static const _notAdmin = 'not-admin';
  static const _invalidInput = 'invalid-input';
  static const _requestIdReused = 'request-id-reused';
  static const _noThread = 'no-thread';
  static const _noEmail = 'no-email';
  static const _inProgress = 'in-progress';
  static const _sendFailed = 'send-failed';
  static const _outcomeUnknown = 'outcome-unknown';

  /// `status` as stored.
  static const _stored = {
    ThreadStatus.unreplied: 'open',
    ThreadStatus.replied: 'replied',
    ThreadStatus.closed: 'closed',
  };

  Query<Map<String, Object?>> get _threads =>
      _firestore.collectionGroup('feedback');

  @override
  Stream<List<SupportThread>> watchThreads(ThreadFilter filter) => _failures(
    switch (filter) {
          ThreadFilter.open => _threads.where(
            'status',
            whereIn: [
              _stored[ThreadStatus.unreplied],
              _stored[ThreadStatus.replied],
            ],
          ),
          ThreadFilter.closed => _threads.where(
            'status',
            isEqualTo: _stored[ThreadStatus.closed],
          ),
        }
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              threadFromMap(doc.reference.path, doc.data()),
          ],
        ),
  );

  @override
  Stream<int> watchNewCount() => _failures(
    _threads
        .where('status', isEqualTo: _stored[ThreadStatus.unreplied])
        .limit(newCountCap)
        .snapshots()
        .map((snapshot) => snapshot.size),
  );

  @override
  Stream<List<SupportReply>> watchReplies(String threadPath) => _failures(
    _firestore
        .doc(threadPath)
        .collection('replies')
        .orderBy('requestedAt')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) replyFromMap(doc.id, doc.data()),
          ],
        ),
  );

  @override
  Future<Result<void>> setStatus(String path, ThreadStatus status) => guard(
    () => _firestore.doc(path).update({'status': _stored[status]}),
    mapper: mapFirebaseError,
  );

  @override
  Future<Result<void>> sendReply(ReplyRequest request) => guard(
    () => _functions.httpsCallable(function).call<Object?>({
      'requestId': request.id,
      'threadPath': request.threadPath,
      'message': request.message,
      'close': request.close,
    }),
    mapper: _mapError,
  );

  static Stream<T> _failures<T>(Stream<T> stream) => stream.transform(
    StreamTransformer.fromHandlers(
      handleError: (error, stack, sink) {
        final failure =
            mapFirebaseError(error) ?? UnknownFailure('$error', error);
        Log.e('admin', failure.message, error, stack);
        sink.addError(failure, stack);
      },
    ),
  );

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch ((error.code, reason)) {
      (_, _notAdmin) => PermissionFailure(message, error),
      (_, _inProgress) => ReplyInProgressFailure(
        message: message,
        requestedAt: switch ((details as Map)['requestedAt']) {
          final num millis => DateTime.fromMillisecondsSinceEpoch(
            millis.toInt(),
          ),
          _ => null,
        },
        cause: error,
      ),
      (_, _invalidInput || _requestIdReused || _noEmail) => ValidationFailure(
        message,
      ),
      (_, _noThread) => NotFoundFailure(message),
      (_, _sendFailed) => ReplyNotSentFailure(message, error),
      (_, _outcomeUnknown) => ReplyOutcomeUnknownFailure(message, error),
      // Not deployed (404), or deployed without permission to call it.
      ('not-found' || 'permission-denied', _) => RepliesUnavailableFailure(
        message,
        error,
      ),
      _ => mapFirebaseError(error),
    };
  }

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;

  static SupportThread threadFromMap(String path, Map<String, Object?> data) {
    String text(String field) => switch (data[field]) {
      final String value => value,
      _ => '',
    };
    return SupportThread(
      path: path,
      uid: text('uid'),
      email: switch (data['email']) {
        final String email when email.isNotEmpty => email,
        _ => null,
      },
      message: text('message'),
      source: text('source'),
      appVersion: text('appVersion'),
      platform: text('platform'),
      osVersion: text('osVersion'),
      deviceModel: text('deviceModel'),
      locale: text('locale'),
      createdAt: _date(data['createdAt']),
      status: switch (data['status']) {
        'replied' => ThreadStatus.replied,
        'closed' => ThreadStatus.closed,
        _ => ThreadStatus.unreplied,
      },
      lastReplyAt: _date(data['lastReplyAt']),
    );
  }

  static SupportReply replyFromMap(String id, Map<String, Object?> data) =>
      SupportReply(
        id: id,
        message: '${data['message'] ?? ''}',
        to: '${data['to'] ?? ''}',
        status: switch (data['status']) {
          'sending' => ReplyStatus.sending,
          'sent' => ReplyStatus.sent,
          'failed' => ReplyStatus.failed,
          _ => ReplyStatus.unknown,
        },
        sentByEmail: switch (data['sentByEmail']) {
          final String email => email,
          _ => null,
        },
        requestedAt: _date(data['requestedAt']),
        sentAt: _date(data['sentAt']),
      );
}
