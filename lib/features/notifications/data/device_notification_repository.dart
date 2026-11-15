import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/notification_repository.dart';
import '../domain/reminder_plan.dart';
import 'notification_payloads.dart';
import 'notifications_asked_marker.dart';

/// [NotificationRepository] over the app's local notifications, waiting
/// until they are initialised.
class DeviceNotificationRepository implements NotificationRepository {
  const DeviceNotificationRepository(this._notifications, this._asked);

  final Future<Notifications> _notifications;
  final NotificationsAskedMarker _asked;

  @override
  Future<Result<bool>> allowed() async =>
      (await (await _notifications).status()).map(
        (permission) => permission == NotificationPermission.granted,
      );

  @override
  Future<Result<bool>> request() async {
    final result = (await (await _notifications).request()).map(
      (permission) => permission == NotificationPermission.granted,
    );
    if (result.isOk) await _markAsked(_asked);
    return result;
  }

  @override
  Future<Result<bool>> askedHere() => _asked.exists();

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

/// Notes that the device was asked; a failure only logs, as asking again
/// is harmless.
Future<void> _markAsked(NotificationsAskedMarker asked) async {
  if ((await asked.set()).failureOrNull case final failure?) {
    Log.e('notifications', 'not remembered as asked: ${failure.message}');
  }
}
