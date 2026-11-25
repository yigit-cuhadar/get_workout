import 'package:forge_core/forge_core.dart';
import 'package:forge_messaging/forge_messaging.dart';

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

class GetNotificationsAsked implements UseCase<bool, NoParams> {
  const GetNotificationsAsked(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<bool>> call(NoParams params) => _repository.askedHere();
}

class OpenNotificationSettings implements UseCase<void, NoParams> {
  const OpenNotificationSettings(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<void>> call(NoParams params) => _repository.openSettings();
}

class RefreshTimeZone implements UseCase<void, NoParams> {
  const RefreshTimeZone(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<void>> call(NoParams params) => _repository.refreshTimeZone();
}

class SyncReminders implements UseCase<void, ReminderSync> {
  const SyncReminders(this._repository);
  final NotificationRepository _repository;

  @override
  Future<Result<void>> call(ReminderSync params) =>
      _repository.syncReminders(params.kind, params.wanted);
}

/// Takes the announcements of [AnnouncementAudience]'s language, and once
/// the Premium state is known, of the free or the Premium users, leaving
/// the other and every other language's.
class FollowAnnouncements implements UseCase<void, AnnouncementAudience> {
  const FollowAnnouncements(this._topics);
  final TopicRepository _topics;

  @override
  Future<Result<void>> call(AnnouncementAudience audience) => _topics.follow(
    audience.language,
    segment: switch (audience.premium) {
      null => null,
      false => AnnouncementTopics.free,
      true => AnnouncementTopics.premium,
    },
  );
}
