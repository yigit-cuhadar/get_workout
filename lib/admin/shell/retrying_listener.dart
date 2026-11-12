import 'dart:async';

import 'package:forge_core/forge_core.dart';

/// Listens to the stream [watch] gives, and after an error listens again:
/// after [firstRetryDelay], doubling with each failure in a row up to
/// [maxRetryDelay]. Data resets the delay.
class RetryingListener<T> {
  RetryingListener({
    required this._watch,
    required this._onData,
    required this._onFailure,
    required this.firstRetryDelay,
  }) {
    _listen();
  }

  final Stream<T> Function() _watch;
  final void Function(T value) _onData;
  final void Function(Failure failure) _onFailure;
  final Duration firstRetryDelay;
  static const maxRetryDelay = Duration(seconds: 30);

  StreamSubscription<T>? _subscription;
  Timer? _retryTimer;
  int _failures = 0;

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = _watch().listen(
      (value) {
        _failures = 0;
        _onData(value);
      },
      onError: (Object error) {
        _onFailure(error is Failure ? error : UnknownFailure('$error', error));
        final delay = firstRetryDelay * (1 << _failures.clamp(0, 10));
        _failures++;
        _retryTimer?.cancel();
        _retryTimer = Timer(
          delay < maxRetryDelay ? delay : maxRetryDelay,
          _listen,
        );
      },
    );
  }

  /// Listens again now, without waiting for the next automatic retry.
  void retry() {
    _retryTimer?.cancel();
    _listen();
  }

  Future<void> cancel() async {
    _retryTimer?.cancel();
    await _subscription?.cancel();
  }
}
