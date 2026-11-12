import 'dart:math';

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

/// An announcement as the admin types it. It goes to the devices that follow
/// [locale]'s topic, `announcements_<locale>`.
class AnnouncementDraft extends Equatable {
  const AnnouncementDraft({
    this.locale = 'en',
    this.title = '',
    this.body = '',
  });

  final String locale;
  final String title;
  final String body;

  /// The text as it is sent.
  AnnouncementDraft get trimmed =>
      AnnouncementDraft(locale: locale, title: title.trim(), body: body.trim());

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

  AnnouncementDraft copyWith({String? locale, String? title, String? body}) =>
      AnnouncementDraft(
        locale: locale ?? this.locale,
        title: title ?? this.title,
        body: body ?? this.body,
      );

  @override
  List<Object?> get props => [locale, title, body];
}

/// Where a recorded announcement stands; [unknown] for a status this panel
/// does not know.
enum AnnouncementStatus { sending, sent, failed, unknown }

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
  });

  /// The request id.
  final String id;
  final String locale;
  final String title;
  final String body;
  final AnnouncementStatus status;

  /// The uid of the admin who sent it.
  final String sentBy;
  final DateTime? requestedAt;
  final DateTime? sentAt;

  @override
  List<Object?> get props => [
    id,
    locale,
    title,
    body,
    status,
    sentBy,
    requestedAt,
    sentAt,
  ];
}

/// A send that went through.
class SentAnnouncement extends Equatable {
  const SentAnnouncement({required this.messageId, required this.alreadySent});

  /// FCM's id of the message.
  final String messageId;

  /// The request was sent before (a retry); nothing was sent this time.
  final bool alreadySent;

  @override
  List<Object?> get props => [messageId, alreadySent];
}

/// A request to send [draft] under the request [id]: the same id sends
/// once, so a retry after an unclear failure never sends twice.
typedef AnnouncementRequest = ({String id, AnnouncementDraft draft});

/// A new request id, as `sendAnnouncement` accepts it: 20 random letters
/// and digits.
String newAnnouncementRequestId() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 20; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}

/// `sendAnnouncement` cannot be called: it is not deployed to this project,
/// or deployed without permission to call it. Nothing was sent.
final class AnnouncementsUnavailableFailure extends Failure {
  const AnnouncementsUnavailableFailure([
    super.message = 'sendAnnouncement cannot be called',
    Object? cause,
  ]) : super(cause: cause);
}

/// The same request is being sent right now; its outcome shows in the
/// history.
final class AnnouncementInProgressFailure extends Failure {
  const AnnouncementInProgressFailure([
    super.message = 'announcement being sent',
    Object? cause,
  ]) : super(cause: cause);
}
