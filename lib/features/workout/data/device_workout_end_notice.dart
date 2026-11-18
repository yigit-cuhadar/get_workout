import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/workout_end_notice.dart';

/// [WorkoutEndNotice] as a local notification on the app's `workout`
/// channel, once the notifications are initialised. Shown only where the
/// device lets the app notify; nothing asks for it.
class DeviceWorkoutEndNotice implements WorkoutEndNotice {
  const DeviceWorkoutEndNotice(this._notifications);

  final Future<Notifications> _notifications;

  /// After the rest's (1) and the lock screen's (2, 3).
  static const id = 4;

  @override
  Future<Result<void>> schedule(
    DateTime at, {
    required String title,
    required String body,
  }) async =>
      (await _notifications).scheduleAt(id, at, title: title, body: body);

  @override
  Future<Result<void>> cancel() async => (await _notifications).cancel(id);
}
