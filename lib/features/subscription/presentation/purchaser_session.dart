import 'dart:async';

import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';

/// Keeps the store's user equal to the signed-in user: [EntitlementCubit]
/// identifies the uid (a guest's too; linking keeps it, so nothing changes)
/// and resets when nobody is signed in. Until a switch succeeds the
/// entitlement stays unknown, so a failed switch is retried after
/// [retryDelay], doubling up to [maxRetryDelay], or at once on [resume].
class PurchaserSession {
  PurchaserSession({
    required WatchAuthUser watchAuthUser,
    required this._entitlement,
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 30),
  }) : _nextDelay = retryDelay {
    _users = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_userChanged);
  }

  final Duration retryDelay;
  final Duration maxRetryDelay;
  final EntitlementCubit _entitlement;
  late final StreamSubscription<String?> _users;
  Timer? _retry;
  Duration _nextDelay;
  String? _uid;
  bool _cancelled = false;

  void _userChanged(String? uid) {
    _uid = uid;
    _retry?.cancel();
    _retry = null;
    _nextDelay = retryDelay;
    unawaited(_switch());
  }

  Future<void> _switch() async {
    final uid = _uid;
    final result = uid == null
        ? await _entitlement.reset()
        : await _entitlement.identify(uid);
    // A later user change has started its own switch.
    if (_cancelled || uid != _uid || result.isOk) return;
    Log.e(
      'purchases',
      'Switching the store user failed; retrying in $_nextDelay',
      result.failureOrNull,
    );
    _retry = Timer(_nextDelay, resume);
    final doubled = _nextDelay * 2;
    _nextDelay = doubled > maxRetryDelay ? maxRetryDelay : doubled;
  }

  /// Retries a failed switch at once, e.g. when the app comes back.
  void resume() {
    if (_retry == null || _cancelled) return;
    _retry!.cancel();
    _retry = null;
    unawaited(_switch());
  }

  Future<void> cancel() async {
    _cancelled = true;
    _retry?.cancel();
    await _users.cancel();
  }
}
