import 'package:forge_core/forge_core.dart';

/// Where a thread stands. Stored in `status` as `open` (New: not replied
/// to yet; the app writes it), `replied` (set by sending a reply) and
/// `closed`.
enum ThreadStatus {
  /// Shown as New.
  unreplied,
  replied,
  closed,
}

/// The inbox's two lists: New and Replied threads under Open, then Closed.
enum ThreadFilter { open, closed }

/// A message a user sent from the app's Help & feedback form, as stored in
/// `users/{uid}/feedback/{id}`, with the replies kept under it.
class SupportThread extends Equatable {
  const SupportThread({
    required this.path,
    required this.uid,
    required this.email,
    required this.message,
    required this.source,
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
    required this.locale,
    required this.createdAt,
    required this.status,
    required this.lastReplyAt,
  });

  /// The document's path, which names it across users.
  final String path;
  final String uid;

  /// Where a reply goes; null when the user left none, so none can.
  final String? email;
  final String message;

  /// `profile` or `rating`, as stored.
  final String source;
  final String appVersion;
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String locale;

  /// Null while the server time is pending.
  final DateTime? createdAt;
  final ThreadStatus status;

  /// When the last reply went out; null before the first.
  final DateTime? lastReplyAt;

  bool get canReply => email != null;

  /// The status a closed thread goes back to: replied once it was.
  ThreadStatus get reopenedStatus =>
      lastReplyAt == null ? ThreadStatus.unreplied : ThreadStatus.replied;

  @override
  List<Object?> get props => [
    path,
    uid,
    email,
    message,
    source,
    appVersion,
    platform,
    osVersion,
    deviceModel,
    locale,
    createdAt,
    status,
    lastReplyAt,
  ];
}

/// Where a reply stands; [unknown] for a status this panel does not know.
enum ReplyStatus { sending, sent, failed, unknown }

/// How long a send may take before a reply still `sending` is taken as one
/// whose outcome is unknown (the function died, or Gmail did not say).
const staleReplyAfter = Duration(minutes: 5);

/// A reply emailed to the thread's sender, as `sendSupportReply` keeps it
/// in `{thread}/replies/{requestId}`.
class SupportReply extends Equatable {
  const SupportReply({
    required this.id,
    required this.message,
    required this.to,
    required this.status,
    required this.sentByEmail,
    required this.requestedAt,
    required this.sentAt,
  });

  /// The request id.
  final String id;
  final String message;

  /// The address it was emailed to.
  final String to;
  final ReplyStatus status;

  /// The sending admin's email; null when their account has none.
  final String? sentByEmail;
  final DateTime? requestedAt;
  final DateTime? sentAt;

  /// Still `sending` long after it was requested: it may or may not have
  /// reached the sender, and it is never sent again.
  bool outcomeUnknownAt(DateTime now) =>
      status == ReplyStatus.sending &&
      requestedAt != null &&
      now.difference(requestedAt!) > staleReplyAfter;

  @override
  List<Object?> get props => [
    id,
    message,
    to,
    status,
    sentByEmail,
    requestedAt,
    sentAt,
  ];
}

/// The longest reply `sendSupportReply` accepts, in UTF-16 code units like
/// [String.length] and the function.
const maxReplyLength = 5000;

/// The subject and sender every reply goes out with
/// (`functions/src/send_support_reply.ts`).
const replySubject = 'Re: Your message to GetWorkout';
const supportAddress = 'getworkout.support@gmail.com';

/// A reply to send: [message] to the thread at [threadPath] under the
/// request [id], which the server sends once, so a retry after an unclear
/// failure never sends twice. With [close] the thread ends closed.
typedef ReplyRequest = ({
  String id,
  String threadPath,
  String message,
  bool close,
});

/// `sendSupportReply` cannot be called: it is not deployed to this
/// project, or deployed without permission to call it. Nothing was sent.
final class RepliesUnavailableFailure extends Failure {
  const RepliesUnavailableFailure([
    super.message = 'sendSupportReply cannot be called',
    Object? cause,
  ]) : super(cause: cause);
}

/// The same request is `sending`: right now, or, long after [requestedAt],
/// with an outcome nobody knows. It is never sent again.
final class ReplyInProgressFailure extends Failure {
  const ReplyInProgressFailure({
    String message = 'reply being sent',
    this.requestedAt,
    Object? cause,
  }) : super(message, cause: cause);

  /// When the request was made; null when the server did not say.
  final DateTime? requestedAt;
}

/// Gmail certainly did not take the reply: nothing was sent, and sending
/// it again may send it.
final class ReplyNotSentFailure extends Failure {
  const ReplyNotSentFailure([super.message = 'reply not sent', Object? cause])
    : super(cause: cause);
}

/// Gmail may or may not have taken the reply. It stays `sending` and is
/// never sent again.
final class ReplyOutcomeUnknownFailure extends Failure {
  const ReplyOutcomeUnknownFailure([
    super.message = 'reply outcome unknown',
    Object? cause,
  ]) : super(cause: cause);
}
