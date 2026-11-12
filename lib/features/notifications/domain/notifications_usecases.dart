import 'package:forge_core/forge_core.dart';

import 'notification_repository.dart';
import 'reminder_plan.dart';

typedef ReminderSync = ({ReminderKind kind, List<ReminderNotice> wanted});

class GetNotificationAccess implements UseCase<bool, NoParams> {
  const GetNotificationAccess(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<bool>> call(NoParams params) => _repository.allowed();
}

class RequestNotificationAccess implements UseCase<bool, NoParams> {
  const RequestNotificationAccess(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<bool>> call(NoParams params) => _repository.request();
}

class OpenNotificationSettings implements UseCase<void, NoParams> {
  const OpenNotificationSettings(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<void>> call(NoParams params) => _repository.openSettings();
}

class RefreshTimeZone implements UseCase<bool, NoParams> {
  const RefreshTimeZone(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<bool>> call(NoParams params) => _repository.refreshTimeZone();
}

class SyncReminders implements UseCase<void, ReminderSync> {
  const SyncReminders(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<void>> call(ReminderSync params) =>
      _repository.syncReminders(params.kind, params.wanted);
}

/// Takes the announcements of a language (`announcements_<code>`).
class FollowAnnouncements implements UseCase<void, String> {
  const FollowAnnouncements(this._repository);
  final AnnouncementRepository _repository;

  @override
  Future<Result<void>> call(String language) => _repository.follow(language);
}
