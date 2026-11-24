import 'dart:async';

import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/devices_usecases.dart';

/// Records this install for each user signed in: at launch, after every
/// sign-in or account switch, and when the push token changes
/// ([RecordDevice] decides whether to write).
class DeviceSession {
  DeviceSession({
    required WatchAuthUser watchAuthUser,
    required this._recordDevice,
    required WatchPushTokenChanges watchPushTokenChanges,
  }) {
    _subscriptions = [
      watchAuthUser().map((user) => user?.id).distinct().listen((uid) {
        _uid = uid;
        if (uid != null) unawaited(_record(uid));
      }),
      watchPushTokenChanges().listen((_) {
        if (_uid case final uid?) unawaited(_record(uid));
      }),
    ];
  }

  final RecordDevice _recordDevice;
  late final List<StreamSubscription<Object?>> _subscriptions;
  String? _uid;

  Future<void> _record(String uid) async {
    final result = await _recordDevice(uid);
    if (result.failureOrNull case final failure?) {
      Log.e('devices', 'not recorded: ${failure.message}');
    }
  }

  Future<void> cancel() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
