import 'package:forge_core/forge_core.dart';

/// The notification that a rest is over, on this device. Whether the user
/// wants it is theirs (`settings.restTimer.notify`, on every device);
/// whether the device allows it, and whether they were asked here, belong
/// to the device.
abstract interface class RestNotifications {
  /// Whether the device lets the app notify.
  Future<Result<bool>> allowed();

  /// Asks the device to let the app notify, then, where alarms are not
  /// exact, to make them exact (they may come late otherwise); returns
  /// whether it may notify.
  Future<Result<bool>> request();

  /// Replaces any pending rest notification with one at [at].
  Future<Result<void>> schedule(
    DateTime at, {
    required String title,
    required String body,
  });

  /// Cancels the pending or shown rest notification.
  Future<Result<void>> cancel();

  /// Whether the user was asked about it on this device.
  Future<Result<bool>> askedHere();

  Future<Result<void>> markAskedHere();
}
