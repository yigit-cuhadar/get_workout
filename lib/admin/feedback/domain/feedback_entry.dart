import 'package:forge_core/forge_core.dart';

/// Whether a message still needs the team; stored as its name.
enum FeedbackEntryStatus { open, closed }

/// A message a user sent from the app's Help & feedback form, as stored in
/// `users/{uid}/feedback/{id}`.
class FeedbackEntry extends Equatable {
  const FeedbackEntry({
    required this.path,
    required this.uid,
    required this.email,
    required this.message,
    required this.source,
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
    required this.locale,
    required this.createdAt,
    required this.status,
  });

  /// The document's path, which names it across users.
  final String path;
  final String uid;

  /// Where to reply; null when the user left none.
  final String? email;
  final String message;

  /// `profile` or `rating`, as stored.
  final String source;
  final String appVersion;
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String locale;

  /// Null while the server time is pending.
  final DateTime? createdAt;
  final FeedbackEntryStatus status;

  @override
  List<Object?> get props => [
    path,
    uid,
    email,
    message,
    source,
    appVersion,
    platform,
    osVersion,
    deviceModel,
    locale,
    createdAt,
    status,
  ];
}
