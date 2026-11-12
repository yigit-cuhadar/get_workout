import 'package:forge_core/forge_core.dart';

import 'announcement.dart';

/// Push announcements, sent by the callable `sendAnnouncement`, which needs
/// the admin claim, and their history in `announcements`.
abstract interface class AdminAnnouncementRepository {
  /// The latest announcements, newest first, again whenever one changes.
  /// Errors are [Failure]s.
  Stream<List<Announcement>> watchHistory();

  /// Sends [request]'s draft as it is (trim and check it first). Fails with
  /// [PermissionFailure] without the admin claim,
  /// [AnnouncementsUnavailableFailure] when the function cannot be called,
  /// [AnnouncementInProgressFailure] while the same request is being sent,
  /// [ValidationFailure] when the function refuses the input and
  /// [NetworkFailure] offline.
  Future<Result<SentAnnouncement>> send(AnnouncementRequest request);
}
