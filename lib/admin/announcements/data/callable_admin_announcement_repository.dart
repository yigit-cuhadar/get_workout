import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/admin_announcement_repository.dart';
import '../domain/announcement.dart';

/// Sends through the callable `sendAnnouncement`
/// (`functions/src/send_announcement.ts`) and reads the history it writes
/// to `announcements`, which only admins may read.
class CallableAdminAnnouncementRepository
    implements AdminAnnouncementRepository {
  const CallableAdminAnnouncementRepository(this._functions, this._firestore);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  static const function = 'sendAnnouncement';

  /// How many of the latest announcements the history shows.
  static const historyLength = 50;

  /// `details.reason` values of the function's refusals.
  static const _notAdmin = 'not-admin';
  static const _inProgress = 'in-progress';
  static const _invalidInput = 'invalid-input';
  static const _requestIdReused = 'request-id-reused';

  @override
  Stream<List<Announcement>> watchHistory() => _firestore
      .collection('announcements')
      .orderBy('requestedAt', descending: true)
      .limit(historyLength)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) _announcement(doc.id, doc.data()),
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
  Future<Result<SentAnnouncement>> send(AnnouncementRequest request) =>
      guard(() async {
        final draft = request.draft;
        final result = await _functions.httpsCallable(function).call<Object?>({
          'requestId': request.id,
          'locale': draft.locale,
          'title': draft.title,
          'body': draft.body,
        });
        final data = result.data;
        if (data is! Map) throw UnknownFailure('unexpected result: $data');
        return SentAnnouncement(
          messageId: '${data['messageId'] ?? ''}',
          alreadySent: data['alreadySent'] == true,
        );
      }, mapper: _mapError);

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch ((error.code, reason)) {
      (_, _notAdmin) => PermissionFailure(message, error),
      (_, _inProgress) => AnnouncementInProgressFailure(message, error),
      (_, _invalidInput || _requestIdReused) => ValidationFailure(message),
      // Not deployed (404), or deployed without permission to call it.
      ('not-found' || 'permission-denied', _) =>
        AnnouncementsUnavailableFailure(message, error),
      _ => mapFirebaseError(error),
    };
  }

  static Announcement _announcement(String id, Map<String, Object?> data) =>
      Announcement(
        id: id,
        locale: '${data['locale'] ?? ''}',
        title: '${data['title'] ?? ''}',
        body: '${data['body'] ?? ''}',
        status: switch (data['status']) {
          'sending' => AnnouncementStatus.sending,
          'sent' => AnnouncementStatus.sent,
          'failed' => AnnouncementStatus.failed,
          _ => AnnouncementStatus.unknown,
        },
        sentBy: '${data['sentBy'] ?? ''}',
        requestedAt: _date(data['requestedAt']),
        sentAt: _date(data['sentAt']),
      );

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;
}
