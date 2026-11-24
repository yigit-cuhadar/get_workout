import 'package:forge_core/forge_core.dart';

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
