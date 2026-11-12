import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/notification_repository.dart';
import '../domain/reminder_plan.dart';
import 'notification_taps.dart';

/// [NotificationRepository] over the app's local notifications, waiting
/// until they are initialised.
class DeviceNotificationRepository implements NotificationRepository {
  const DeviceNotificationRepository(this._notifications);

  final Future<Notifications> _notifications;

  @override
  Future<Result<bool>> allowed() async =>
      (await (await _notifications).status()).map(
        (permission) => permission == NotificationPermission.granted,
      );

  @override
  Future<Result<bool>> request() async =>
      (await (await _notifications).request()).map(
        (permission) => permission == NotificationPermission.granted,
      );

  @override
  Future<Result<void>> openSettings() async =>
      (await _notifications).openSettings();

  @override
  Future<Result<void>> refreshTimeZone() async =>
      (await (await _notifications).refreshTimeZone()).map((_) {});

  @override
  Future<Result<void>> syncReminders(
    ReminderKind kind,
    List<ReminderNotice> wanted,
  ) async {
    final ids = ReminderIds.of(kind);
    final payload = NotificationPayloads.reminder(kind);
    return (await _notifications).sync(
      ids.base,
      count: ids.count,
      wanted: [
        for (final notice in wanted)
          OneOffNotification(
            notice.id,
            notice.at,
            title: notice.title,
            body: notice.body,
            payload: payload,
          ),
      ],
    );
  }
}
