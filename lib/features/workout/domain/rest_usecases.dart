import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';

import 'rest_chime.dart';
import 'rest_notifications.dart';

/// The rest notification's text and time.
typedef RestNotice = ({
  DateTime at,
  String title,
  String body,
  RestAlert alert,
});

/// What to do about the rest notification as a workout starts.
enum RestNotifyAsk {
  /// Nothing to ask.
  none,

  /// Ask the user in the app.
  ask,

  /// Take it as a yes without asking: the user never answered and this
  /// device already allows notifications (e.g. from onboarding).
  allow,
}

/// What to do about the rest notification, given the user's [wish]: never
/// ask after a no, nor twice on one device, nor when they said yes and this
/// device already allows it; with no wish on a device that already allows
/// it, a yes without asking. The device itself is only asked once they
/// answer ([AllowRestNotifications]), never on its own. A failure to tell
/// whether the device was asked asks nothing.
class ShouldAskRestNotifications {
  const ShouldAskRestNotifications(this._notifications);
  final RestNotifications _notifications;

  Future<RestNotifyAsk> call(bool? wish) async {
    if (wish == false) return RestNotifyAsk.none;
    final asked = await _notifications.askedHere();
    if (asked.valueOrNull != false) return RestNotifyAsk.none;
    final allowed = (await _notifications.allowed()).valueOrNull;
    if (wish == null) {
      return allowed == true ? RestNotifyAsk.allow : RestNotifyAsk.ask;
    }
    return allowed == false ? RestNotifyAsk.ask : RestNotifyAsk.none;
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

class PlayRestChime implements UseCase<void, NoParams> {
  const PlayRestChime(this._chime);
  final RestChime _chime;

  @override
  Future<Result<void>> call(NoParams params) => _chime.play();
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
    alert: params.alert,
  );
}

class CancelRestNotification implements UseCase<void, NoParams> {
  const CancelRestNotification(this._notifications);
  final RestNotifications _notifications;

  @override
  Future<Result<void>> call(NoParams params) => _notifications.cancel();
}
