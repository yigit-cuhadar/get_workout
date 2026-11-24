import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import 'device.dart';
import 'device_repository.dart';

/// Records this install under the signed-in user [params] (a uid), for
/// the admin panel's Devices and test announcements. It writes only when
/// the user, the device's model, platform, OS version, app version or push
/// token changed since this install last wrote, or that was [refreshAfter]
/// ago or more, so "last seen" is right to the day without a write on
/// every launch. True when it wrote.
class RecordDevice implements UseCase<bool, String> {
  const RecordDevice(this._repository, this._now);
  final DeviceRepository _repository;
  final DateTime Function() _now;

  static const refreshAfter = Duration(hours: 24);

  /// The platforms the rules accept; other builds record nothing.
  static const platforms = {'ios', 'android'};

  @override
  Future<Result<bool>> call(String params) async {
    final current = await _repository.current();
    final device = current.valueOrNull;
    if (device == null) return Err(current.failureOrNull!);
    if (!platforms.contains(device.platform)) return const Ok(false);
    // An unreadable last record only costs a write.
    final last = (await _repository.lastRecord()).valueOrNull;
    final now = _now();
    if (last != null &&
        last.uid == params &&
        last.device == device &&
        now.difference(last.at) < refreshAfter) {
      return const Ok(false);
    }
    return (await _repository.record(params, device, now)).map((_) => true);
  }
}

class WatchPushTokenChanges {
  const WatchPushTokenChanges(this._repository);
  final DeviceRepository _repository;

  Stream<void> call() => _repository.pushTokenChanges();
}

/// Clears the push token from [params]'s (a uid) record of this install,
/// so the panel's test announcements stop reaching a device they leave.
/// Nothing is written when this install last recorded them without one.
/// Gives up after [limit]: offline, the sign-out does not wait for it.
class ForgetPushToken implements UseCase<void, String> {
  const ForgetPushToken(this._repository, this._now);
  final DeviceRepository _repository;
  final DateTime Function() _now;

  static const limit = Duration(seconds: 3);

  @override
  Future<Result<void>> call(String params) async {
    final last = (await _repository.lastRecord()).valueOrNull;
    if (last != null && last.uid == params && last.device.pushToken == null) {
      return const Ok(null);
    }
    final current = await _repository.current();
    final device = current.valueOrNull;
    if (device == null) return Err(current.failureOrNull!);
    if (!RecordDevice.platforms.contains(device.platform)) {
      return const Ok(null);
    }
    final cleared = Device(
      installId: device.installId,
      model: device.model,
      platform: device.platform,
      osVersion: device.osVersion,
      appVersion: device.appVersion,
    );
    return _repository
        .record(params, cleared, _now())
        // A future typed by its value (Ok) would refuse the Err below.
        .then<Result<void>>((result) => result)
        .timeout(limit, onTimeout: () => const Err(NetworkFailure()));
  }
}

/// forge_auth's [SignOut] that first clears this install's push token from
/// the signed-in user's record ([ForgetPushToken]); the sign-out goes on
/// whatever that gives. Both of the app's sign-outs (Account and the email
/// verification page) take it from `SignOut`.
class SignOutForgettingPushToken extends SignOut {
  const SignOutForgettingPushToken(
    super.repository,
    this._getCurrentUser,
    this._forgetPushToken,
  );
  final GetCurrentUser _getCurrentUser;
  final ForgetPushToken _forgetPushToken;

  @override
  Future<Result<void>> call([NoParams params = const NoParams()]) async {
    if (_getCurrentUser() case final user?) {
      final forgotten = await _forgetPushToken(user.id);
      if (forgotten.failureOrNull case final failure?) {
        Log.e('devices', 'push token left: ${failure.message}');
      }
    }
    return super.call(params);
  }
}
