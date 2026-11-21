import 'package:forge_core/forge_core.dart';

import 'device.dart';

abstract interface class DeviceRepository {
  /// This install and the device it runs on.
  Future<Result<Device>> current();

  /// The last record this install wrote; null before the first.
  Future<Result<DeviceRecord?>> lastRecord();

  /// Writes [device] to `users/{uid}/devices/{installId}` with the server
  /// time as `lastSeenAt`, then keeps it on the device as the last record,
  /// made [at].
  Future<Result<void>> record(String uid, Device device, DateTime at);
}
