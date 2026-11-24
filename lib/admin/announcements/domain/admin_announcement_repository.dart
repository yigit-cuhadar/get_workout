import 'package:forge_core/forge_core.dart';

import 'announcement.dart';

/// Push announcements, sent, tested and scheduled by the callable
/// `sendAnnouncement` and cancelled by `cancelAnnouncement`, which need the
/// admin claim, and their history in `announcements`.
abstract interface class AdminAnnouncementRepository {
  /// The latest announcements, newest first, again whenever one changes.
  /// Errors are [Failure]s.
  Stream<List<Announcement>> watchHistory();

  /// Sends [request]'s draft as it is (trim and check it first), or
  /// schedules it when it has a time. Fails with [PermissionFailure]
  /// without the admin claim, [AnnouncementsUnavailableFailure] when the
  /// function cannot be called, [AnnouncementInProgressFailure] while the
  /// same request is `sending`, [AnnouncementNotSentFailure] when FCM
  /// certainly refused it, [AnnouncementOutcomeUnknownFailure] when FCM may
  /// have taken it, [AnnouncementNotScheduledFailure] when its task was not
  /// created, [AnnouncementCancelledFailure] when the request was
  /// cancelled, [ValidationFailure] when the function refuses the input and
  /// [NetworkFailure] offline.
  Future<Result<SentAnnouncement>> send(AnnouncementRequest request);

  /// Sends [draft] now to the calling admin's own devices only, unrecorded
  /// (its audience and time do not matter). Fails with
  /// [NoTestDevicesFailure] when none of them has a push token,
  /// [AnnouncementNotSentFailure] when it reached none, and otherwise as
  /// [send].
  Future<Result<TestAnnouncementResult>> sendTest(AnnouncementDraft draft);

  /// Cancels the scheduled request [id]; cancelling it again succeeds.
  /// Fails with [AnnouncementNotCancellableFailure] when it is not
  /// scheduled (sent, being sent, failed, or unknown), and otherwise as
  /// [send].
  Future<Result<void>> cancel(String id);
}
