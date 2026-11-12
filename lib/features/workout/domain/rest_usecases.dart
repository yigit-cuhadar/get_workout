import 'package:forge_core/forge_core.dart';

import 'rest_lock_screen.dart';
import 'rest_notifications.dart';

/// The rest notification's text and time.
typedef RestNotice = ({DateTime at, String title, String body});

/// Whether to ask the user, in the app, about the rest notification, given
/// their [wish]: never after a no, never twice on one device, and not
/// when they said yes and this device already allows it. The device itself
/// is only asked once they answer ([AllowRestNotifications]), never on its
/// own. A failure to tell asks nothing.
class ShouldAskRestNotifications {
  const ShouldAskRestNotifications(this._notifications);
  final RestNotifications _notifications;

  Future<bool> call(bool? wish) async {
    if (wish == false) return false;
    final asked = await _notifications.askedHere();
    if (asked.valueOrNull != false) return false;
    if (wish == null) return true;
    return (await _notifications.allowed()).valueOrNull == false;
  }
}

/// The user said yes on this device: asks the device; whether it may
/// notify.
class AllowRestNotifications implements UseCase<bool, NoParams> {
  const AllowRestNotifications(this._notifications);
  final RestNotifications _notifications;

  @override
  Future<Result<bool>> call(NoParams params) async {
    await _notifications.markAskedHere();
    return _notifications.request();
  }
}

/// The user said "not now" on this device; other devices still ask.
class DeclineRestNotifications implements UseCase<void, NoParams> {
  const DeclineRestNotifications(this._notifications);
  final RestNotifications _notifications;

  @override
  Future<Result<void>> call(NoParams params) => _notifications.markAskedHere();
}

class ScheduleRestNotification implements UseCase<void, RestNotice> {
  const ScheduleRestNotification(this._notifications);
  final RestNotifications _notifications;

  @override
  Future<Result<void>> call(RestNotice params) => _notifications.schedule(
    params.at,
    title: params.title,
    body: params.body,
  );
}

class CancelRestNotification implements UseCase<void, NoParams> {
  const CancelRestNotification(this._notifications);
  final RestNotifications _notifications;

  @override
  Future<Result<void>> call(NoParams params) => _notifications.cancel();
}

class ShowRestOnLockScreen implements UseCase<void, RestCountdown> {
  const ShowRestOnLockScreen(this._lockScreen);
  final RestLockScreen _lockScreen;

  @override
  Future<Result<void>> call(RestCountdown params) => _lockScreen.show(params);
}

class ClearRestFromLockScreen implements UseCase<void, NoParams> {
  const ClearRestFromLockScreen(this._lockScreen);
  final RestLockScreen _lockScreen;

  @override
  Future<Result<void>> call(NoParams params) => _lockScreen.clear();
}
