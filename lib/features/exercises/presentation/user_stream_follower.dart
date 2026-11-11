import 'dart:async';

import 'package:forge_core/forge_core.dart';

/// Follows a per-user stream for whoever is signed in: [onUser] on every
/// change of user (also to none), then [onData] for that user's values.
///
/// A stream that fails is followed again after [retryDelay], doubling up to
/// [maxRetryDelay] while it keeps failing, or at once on [resume], so the
/// values never stay stale after a dropped listener.
class UserStreamFollower<T> {
  UserStreamFollower({
    required Stream<String?> userIds,
    required this._watch,
    required this._onUser,
    required this._onData,
    required this._logTag,
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 30),
  }) : _nextDelay = retryDelay {
    _users = userIds.distinct().listen(_userChanged);
  }

  final Duration retryDelay;
  final Duration maxRetryDelay;
  final Stream<T> Function(String uid) _watch;
  final void Function(String? uid) _onUser;
  final void Function(T value) _onData;
  final String _logTag;
  late final StreamSubscription<String?> _users;
  StreamSubscription<T>? _values;
  Timer? _retry;
  Duration _nextDelay;
  String? _uid;

  /// The signed-in user, or null.
  String? get uid => _uid;

  void _userChanged(String? uid) {
    _uid = uid;
    _stop();
    _nextDelay = retryDelay;
    _onUser(uid);
    if (uid != null) _follow(uid);
  }

  void _follow(String uid) {
    _values = _watch(uid).listen(
      (value) {
        _nextDelay = retryDelay;
        _onData(value);
      },
      onError: (Object error, StackTrace stack) {
        _values = null;
        Log.e(_logTag, 'Stream failed; retrying in $_nextDelay', error, stack);
        _retry = Timer(_nextDelay, resume);
        final doubled = _nextDelay * 2;
        _nextDelay = doubled > maxRetryDelay ? maxRetryDelay : doubled;
      },
      cancelOnError: true,
    );
  }

  /// Follows the stream again at once if it failed. Call before acting for
  /// the user, so the outcome shows up.
  void resume() {
    _retry?.cancel();
    _retry = null;
    final uid = _uid;
    if (uid != null && _values == null) _follow(uid);
  }

  void _stop() {
    _retry?.cancel();
    _retry = null;
    unawaited(_values?.cancel());
    _values = null;
  }

  Future<void> cancel() async {
    _stop();
    await _users.cancel();
  }
}
