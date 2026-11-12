import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/notification_repository.dart';
import '../domain/reminder_plan.dart';
import 'notification_taps.dart';

/// [NotificationRepository] over the app's local notifications, waiting
/// until they are initialised.
class DeviceNotificationRepository implements NotificationRepository {
  const DeviceNotificationRepository(
    this._notifications, {
    this.openSystemSettings = openPluginSettings,
  });

  final Future<Notifications> _notifications;

  /// Opens the app's notification settings; throws when it cannot.
  final Future<void> Function() openSystemSettings;

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
  Future<Result<void>> openSettings() async {
    await _notifications;
    return guard(openSystemSettings);
  }

  @override
  Future<Result<bool>> refreshTimeZone() async =>
      (await (await _notifications).refreshTimeZone()).map(
        (zone) => zone.changed,
      );

  @override
  Future<Result<void>> syncReminders(
    ReminderKind kind,
    List<ReminderNotice> wanted,
  ) async {
    final notifications = await _notifications;
    final pending = await notifications.pending();
    if (pending.failureOrNull case final failure?) return Err(failure);
    final ids = ReminderIds.of(kind).toSet();
    assert(wanted.every((notice) => ids.contains(notice.id)));
    final have = {
      for (final notification in pending.valueOrNull!)
        if (ids.contains(notification.id))
          notification.id: notification.payload,
    };
    final wantedIds = {for (final notice in wanted) notice.id};
    Failure? last;
    for (final id in have.keys) {
      if (wantedIds.contains(id)) continue;
      last = (await notifications.cancel(id)).failureOrNull ?? last;
    }
    for (final notice in wanted) {
      final payload = NotificationPayloads.reminder(kind, notice);
      if (have[notice.id] == payload) continue;
      last =
          (await notifications.scheduleAt(
            notice.id,
            notice.at,
            title: notice.title,
            body: notice.body,
            payload: payload,
          )).failureOrNull ??
          last;
    }
    return last == null ? const Ok(null) : Err(last);
  }

  /// `forge_notifications` cannot open the settings, so this goes to the
  /// plugin, whose instance is shared.
  static Future<void> openPluginSettings() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final opened =
        await (plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.openAppNotificationSettings() ??
            plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.openAppNotificationSettings());
    if (opened != true) {
      throw const UnknownFailure('Notification settings did not open');
    }
  }
}
