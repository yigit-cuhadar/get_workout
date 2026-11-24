import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/admin_announcement_repository.dart';
import '../domain/announcement.dart';

/// Sends, tests and schedules through the callable `sendAnnouncement`
/// (`functions/src/send_announcement.ts`), cancels through
/// `cancelAnnouncement`, and reads the history they write to
/// `announcements`, which only admins may read.
class CallableAdminAnnouncementRepository
    implements AdminAnnouncementRepository {
  const CallableAdminAnnouncementRepository(this._functions, this._firestore);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  static const function = 'sendAnnouncement';
  static const cancelFunction = 'cancelAnnouncement';

  /// `details.reason` values of the functions' refusals.
  static const _notAdmin = 'not-admin';
  static const _inProgress = 'in-progress';
  static const _invalidInput = 'invalid-input';
  static const _requestIdReused = 'request-id-reused';
  static const _sendFailed = 'send-failed';
  static const _outcomeUnknown = 'outcome-unknown';
  static const _scheduleFailed = 'schedule-failed';
  static const _cancelled = 'cancelled';
  static const _noDevices = 'no-devices';
  static const _notScheduled = 'not-scheduled';

  @override
  Stream<List<Announcement>> watchHistory() => _firestore
      .collection('announcements')
      .orderBy('requestedAt', descending: true)
      .limit(announcementHistoryLength)
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

  /// The draft as the function takes it.
  static Map<String, Object?> _input(AnnouncementDraft draft) => {
    'locale': draft.locale,
    'title': draft.title,
    'body': draft.body,
    'audience': draft.audience.name,
  };

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> input,
  ) async {
    final result = await _functions.httpsCallable(name).call<Object?>(input);
    final data = result.data;
    if (data is! Map) throw UnknownFailure('unexpected result: $data');
    return data;
  }

  @override
  Future<Result<SentAnnouncement>> send(AnnouncementRequest request) =>
      guard(() async {
        final scheduleAt = request.draft.scheduleAt;
        final data = await _call(function, {
          'requestId': request.id,
          ..._input(request.draft),
          'scheduleAt': ?scheduleAt?.millisecondsSinceEpoch,
        });
        return SentAnnouncement(
          messageId: '${data['messageId'] ?? ''}',
          alreadySent: data['alreadySent'] == true,
          scheduledFor: switch (data['scheduledFor']) {
            final num millis => DateTime.fromMillisecondsSinceEpoch(
              millis.toInt(),
            ),
            _ => null,
          },
        );
      }, mapper: _mapError);

  @override
  Future<Result<TestAnnouncementResult>> sendTest(AnnouncementDraft draft) =>
      guard(() async {
        final data = await _call(function, {..._input(draft), 'test': true});
        return TestAnnouncementResult(
          delivered: (data['delivered'] as num?)?.toInt() ?? 0,
          failed: (data['failed'] as num?)?.toInt() ?? 0,
        );
      }, mapper: _mapError);

  @override
  Future<Result<void>> cancel(String id) => guard(() async {
    await _call(cancelFunction, {'id': id});
  }, mapper: _mapError);

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch ((error.code, reason)) {
      (_, _notAdmin) => PermissionFailure(message, error),
      (_, _inProgress) => AnnouncementInProgressFailure(
        message: message,
        requestedAt: switch ((details as Map)['requestedAt']) {
          final num millis => DateTime.fromMillisecondsSinceEpoch(
            millis.toInt(),
          ),
          _ => null,
        },
        cause: error,
      ),
      (_, _invalidInput || _requestIdReused) => ValidationFailure(message),
      (_, _sendFailed) => AnnouncementNotSentFailure(message, error),
      (_, _outcomeUnknown) => AnnouncementOutcomeUnknownFailure(message, error),
      (_, _scheduleFailed) => AnnouncementNotScheduledFailure(message, error),
      (_, _cancelled) => AnnouncementCancelledFailure(message, error),
      (_, _noDevices) => NoTestDevicesFailure(message, error),
      (_, _notScheduled) => AnnouncementNotCancellableFailure(message, error),
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
          'scheduled' => AnnouncementStatus.scheduled,
          'sending' => AnnouncementStatus.sending,
          'sent' => AnnouncementStatus.sent,
          'failed' => AnnouncementStatus.failed,
          'cancelled' => AnnouncementStatus.cancelled,
          _ => AnnouncementStatus.unknown,
        },
        audience: switch (data['audience']) {
          'free' => AnnouncementAudience.free,
          'premium' => AnnouncementAudience.premium,
          _ => AnnouncementAudience.everyone,
        },
        scheduledFor: _date(data['scheduledFor']),
        sentBy: '${data['sentBy'] ?? ''}',
        senderEmail: switch (data['senderEmail']) {
          final String email when email.isNotEmpty => email,
          _ => null,
        },
        requestedAt: _date(data['requestedAt']),
        sentAt: _date(data['sentAt']),
      );

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;
}
