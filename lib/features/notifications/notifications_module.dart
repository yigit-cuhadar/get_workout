import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';

import '../../core/device_localizations.dart';

/// Registers local notifications, initialised once in the background;
/// `sl.getAsync<Notifications>()` waits for that. Not for the admin panel.
class NotificationsModule implements FeatureModule {
  const NotificationsModule();

  @override
  void register(GetIt sl) {
    sl.registerSingletonAsync<Notifications>(() async {
      final l10n = deviceLocalizations();
      final notifications = LocalNotifications(
        channel: NotificationChannel(
          id: 'workout',
          name: l10n.notificationChannelName,
          description: l10n.notificationChannelDescription,
          importance: Importance.high,
        ),
        androidIcon: 'ic_notification',
      );
      // On failure every call fails and is logged by its caller; the app
      // works on without notifications.
      if ((await notifications.init()).failureOrNull case final failure?) {
        Log.e('notifications', 'init failed: ${failure.message}');
      }
      return notifications;
    });
  }
}
