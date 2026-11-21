import 'dart:async';

import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/devices_usecases.dart';

/// Records this install for each user signed in: at launch and after every
/// sign-in or account switch ([RecordDevice] decides whether to write).
class DeviceSession {
  DeviceSession({
    required WatchAuthUser watchAuthUser,
    required this._recordDevice,
  }) {
    _subscription = watchAuthUser().map((user) => user?.id).distinct().listen((
      uid,
    ) {
      if (uid != null) unawaited(_record(uid));
    });
  }

  final RecordDevice _recordDevice;
  late final StreamSubscription<String?> _subscription;

  Future<void> _record(String uid) async {
    final result = await _recordDevice(uid);
    if (result.failureOrNull case final failure?) {
      Log.e('devices', 'not recorded: ${failure.message}');
    }
  }

  Future<void> cancel() => _subscription.cancel();
}
