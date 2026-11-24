import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';

/// The longest title and body `sendAnnouncement` accepts
/// (`functions/src/send_announcement.ts`), in UTF-16 code units like
/// [String.length] and the function. Longer text is cut off on most lock
/// screens.
abstract final class AnnouncementLimits {
  static const title = 65;
  static const body = 240;
}

/// Who an announcement goes to, among the devices of its language.
enum AnnouncementAudience { everyone, free, premium }

/// An announcement as the admin types it. It goes to the devices of
/// [locale] in [audience] (`announcements_<locale>`, or its `_free` or
/// `_premium` topic), now or at [scheduleAt].
class AnnouncementDraft extends Equatable {
  const AnnouncementDraft({
    this.locale = 'en',
    this.title = '',
    this.body = '',
    this.audience = AnnouncementAudience.everyone,
    this.scheduleAt,
  });

  final String locale;
  final String title;
  final String body;
  final AnnouncementAudience audience;

  /// When to send it; null sends it now. The function takes a minute to 30
  /// days ahead.
  final DateTime? scheduleAt;

  /// The text as it is sent.
  AnnouncementDraft get trimmed => AnnouncementDraft(
    locale: locale,
    title: title.trim(),
    body: body.trim(),
    audience: audience,
    scheduleAt: scheduleAt,
  );

  /// What `sendAnnouncement` would refuse, by field: `locale`, `title`,
  /// `body`.
  List<ContentProblem> get problems {
    final text = trimmed;
    return [
      if (!languages.contains(locale))
        const ContentProblem('locale', 'not a language of the app'),
      if (text.title.isEmpty) const ContentProblem('title', 'empty'),
      if (text.title.length > AnnouncementLimits.title)
        const ContentProblem(
          'title',
          'longer than ${AnnouncementLimits.title} characters',
        ),
      if (text.body.isEmpty) const ContentProblem('body', 'empty'),
      if (text.body.length > AnnouncementLimits.body)
        const ContentProblem(
          'body',
          'longer than ${AnnouncementLimits.body} characters',
        ),
    ];
  }

  AnnouncementDraft copyWith({
    String? locale,
    String? title,
    String? body,
    AnnouncementAudience? audience,
    DateTime? Function()? scheduleAt,
  }) => AnnouncementDraft(
    locale: locale ?? this.locale,
    title: title ?? this.title,
    body: body ?? this.body,
    audience: audience ?? this.audience,
    scheduleAt: scheduleAt != null ? scheduleAt() : this.scheduleAt,
  );

  @override
  List<Object?> get props => [locale, title, body, audience, scheduleAt];
}

/// Where a recorded announcement stands; [unknown] for a status this panel
/// does not know.
enum AnnouncementStatus { scheduled, sending, sent, failed, cancelled, unknown }

/// How many of the latest announcements the history shows.
const announcementHistoryLength = 50;

/// How long a send may take before a request still `sending` is taken as
/// one whose outcome is unknown (the function died, or FCM did not say).
const staleSendingAfter = Duration(minutes: 5);

/// Whether a request still `sending` since [requestedAt] is stale at [now]:
/// it may or may not have reached devices, and nothing recovers it.
bool isStaleSending(DateTime? requestedAt, DateTime now) =>
    requestedAt != null && now.difference(requestedAt) > staleSendingAfter;

/// One request to send, as `sendAnnouncement` records it in
/// `announcements/{id}`.
class Announcement extends Equatable {
  const Announcement({
    required this.id,
    required this.locale,
    required this.title,
    required this.body,
    required this.status,
    required this.sentBy,
    required this.requestedAt,
    required this.sentAt,
    this.audience = AnnouncementAudience.everyone,
    this.scheduledFor,
    this.senderEmail,
  });

  /// The request id.
  final String id;
  final String locale;
  final String title;
  final String body;
  final AnnouncementStatus status;

  /// Everyone for requests from before audiences.
  final AnnouncementAudience audience;

  /// When a scheduled request is (or was) due; null for one sent at once.
  final DateTime? scheduledFor;

  /// The uid of the admin who sent it.
  final String sentBy;

  /// Their email; null on requests from before it was recorded.
  final String? senderEmail;
  final DateTime? requestedAt;
  final DateTime? sentAt;

  /// Who sent it, as the history shows it: the email, else the uid.
  String get sender => senderEmail ?? sentBy;

  /// Still `sending` long after it was requested ([isStaleSending]).
  bool outcomeUnknownAt(DateTime now) =>
      status == AnnouncementStatus.sending && isStaleSending(requestedAt, now);

  @override
  List<Object?> get props => [
    id,
    locale,
    title,
    body,
    status,
    audience,
    scheduledFor,
    sentBy,
    senderEmail,
    requestedAt,
    sentAt,
  ];
}

/// A send that went through, or a schedule that was stored.
class SentAnnouncement extends Equatable {
  const SentAnnouncement({
    required this.messageId,
    required this.alreadySent,
    this.scheduledFor,
  });

  /// FCM's id of the message; empty for a scheduled one.
  final String messageId;

  /// The request was sent (or scheduled) before, a retry; nothing was done
  /// this time.
  final bool alreadySent;

  /// When it goes, for a scheduled one; null for one sent now.
  final DateTime? scheduledFor;

  bool get scheduled => scheduledFor != null;

  @override
  List<Object?> get props => [messageId, alreadySent, scheduledFor];
}

/// A test sent to the admin's own devices: how many FCM took and refused.
class TestAnnouncementResult extends Equatable {
  const TestAnnouncementResult({required this.delivered, required this.failed});

  final int delivered;
  final int failed;

  @override
  List<Object?> get props => [delivered, failed];
}

/// A test cannot be sent: none of the admin's devices has a push token
/// (notifications not allowed there, or the app not opened since).
final class NoTestDevicesFailure extends Failure {
  const NoTestDevicesFailure([
    super.message = 'no device to test on',
    Object? cause,
  ]) : super(cause: cause);
}

/// A schedule was not stored: its task was not created. Nothing is
/// scheduled; scheduling it again may.
final class AnnouncementNotScheduledFailure extends Failure {
  const AnnouncementNotScheduledFailure([
    super.message = 'announcement not scheduled',
    Object? cause,
  ]) : super(cause: cause);
}

/// The request is not scheduled (any more): it went, or is going, and
/// cannot be cancelled.
final class AnnouncementNotCancellableFailure extends Failure {
  const AnnouncementNotCancellableFailure([
    super.message = 'announcement not scheduled',
    Object? cause,
  ]) : super(cause: cause);
}

/// The request was cancelled; its id never sends.
final class AnnouncementCancelledFailure extends Failure {
  const AnnouncementCancelledFailure([
    super.message = 'announcement cancelled',
    Object? cause,
  ]) : super(cause: cause);
}

/// A request to send [draft] under the request [id]: the server sends an id
/// once, so a retry after an unclear failure never sends twice.
typedef AnnouncementRequest = ({String id, AnnouncementDraft draft});

/// `sendAnnouncement` cannot be called: it is not deployed to this project,
/// or deployed without permission to call it. Nothing was sent.
final class AnnouncementsUnavailableFailure extends Failure {
  const AnnouncementsUnavailableFailure([
    super.message = 'sendAnnouncement cannot be called',
    Object? cause,
  ]) : super(cause: cause);
}

/// The same request is `sending`: right now, or, when [requestedAt] is
/// stale ([isStaleSending]), with an outcome nobody knows. It is never sent
/// again.
final class AnnouncementInProgressFailure extends Failure {
  const AnnouncementInProgressFailure({
    String message = 'announcement being sent',
    this.requestedAt,
    Object? cause,
  }) : super(message, cause: cause);

  /// When the request was made; null when the server did not say.
  final DateTime? requestedAt;
}

/// FCM certainly did not take the announcement: nothing was sent, and
/// sending it again may send it.
final class AnnouncementNotSentFailure extends Failure {
  const AnnouncementNotSentFailure([
    super.message = 'announcement not sent',
    Object? cause,
  ]) : super(cause: cause);
}

/// FCM may or may not have taken the announcement. The request stays
/// `sending` and is never sent again; only a device tells whether it
/// arrived.
final class AnnouncementOutcomeUnknownFailure extends Failure {
  const AnnouncementOutcomeUnknownFailure([
    super.message = 'announcement outcome unknown',
    Object? cause,
  ]) : super(cause: cause);
}
