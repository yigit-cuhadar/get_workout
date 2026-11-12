import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../../workout/domain/workout_repository.dart';
import '../domain/account_repository.dart';

/// A user's data on this device: their kept workouts and every scheduled
/// notification (rest and reminders all belong to whoever is signed in).
/// Firestore's cache is left: clearing it needs the instance shut down,
/// and it is evicted like any cache.
class DeviceAccountData implements LocalAccountData {
  const DeviceAccountData(this._workouts, this._notifications);

  final LocalWorkoutStore _workouts;
  final Future<Notifications> _notifications;

  @override
  Future<Result<void>> clear(String uid) async {
    final results = await Future.wait([
      _workouts.remove(uid),
      _notifications.then((notifications) => notifications.cancelAll()),
    ]);
    return results.firstWhere(
      (result) => !result.isOk,
      orElse: () => const Ok(null),
    );
  }
}
