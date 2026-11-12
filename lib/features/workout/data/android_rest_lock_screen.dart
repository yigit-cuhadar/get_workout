import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/rest_lock_screen.dart';

/// [RestLockScreen] on Android: an ongoing, silent notification whose
/// system chronometer counts down and which the system removes at the end,
/// on the silent `rest` channel (`NotificationsModule`), waiting until
/// notifications are initialised. Shown only where the device lets the app
/// notify; it never asks.
class AndroidRestLockScreen implements RestLockScreen {
  const AndroidRestLockScreen(this._notifications);

  final Future<Notifications> _notifications;

  /// The countdown's id. The rest notification (1) announces the end; this
  /// one never alerts.
  static const id = 2;

  @override
  Future<Result<void>> show(RestCountdown countdown) async =>
      (await _notifications).showCountdown(
        id,
        endsAt: countdown.endsAt,
        title: countdown.title,
        body: countdown.detail,
      );

  @override
  Future<Result<void>> clear() async => (await _notifications).cancel(id);
}
