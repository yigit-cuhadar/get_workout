import 'package:forge_core/forge_core.dart';

/// A running rest as the lock screen shows it: the system counts down to
/// [endsAt] by itself, without the app running.
class RestCountdown extends Equatable {
  const RestCountdown({
    required this.endsAt,
    required this.title,
    this.detail,
    required this.over,
  });

  final DateTime endsAt;
  final String title;

  /// What comes next, e.g. the next set; null when nothing is left.
  final String? detail;

  /// Shown once [endsAt] has passed while the app could not remove it (iOS,
  /// app suspended).
  final String over;

  @override
  List<Object?> get props => [endsAt, title, detail, over];
}

/// The running rest on the lock screen (iOS Live Activity, Android ongoing
/// notification). Silent: the end is announced by the rest notification
/// alone.
abstract interface class RestLockScreen {
  /// Shows [countdown], replacing the one shown.
  Future<Result<void>> show(RestCountdown countdown);

  /// Removes the one shown, if any.
  Future<Result<void>> clear();
}
