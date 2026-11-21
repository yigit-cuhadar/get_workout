import 'package:forge_core/forge_core.dart';
import 'package:intl/intl.dart';

import '../../shell/admin_text.dart';
import '../domain/support_thread.dart';

String threadStatusLabel(ThreadStatus status) => switch (status) {
  ThreadStatus.unreplied => 'New',
  ThreadStatus.replied => 'Replied',
  ThreadStatus.closed => 'Closed',
};

/// When a thread came in, as its row says it at [now]: "Just now", "5m ago",
/// "2h ago" the same day, "Yesterday", then "Nov 18", or "Nov 18, 2025" in
/// another year.
String threadTimeLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Pending';
  final local = at.toLocal();
  final since = now.difference(local);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) {
    if (since.inMinutes < 1) return 'Just now';
    if (since.inHours < 1) return '${since.inMinutes}m ago';
    return '${since.inHours}h ago';
  }
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  return DateFormat(local.year == now.year ? 'MMM d' : 'MMM d, y')
      .format(local);
}

final _fullTime = DateFormat('MMM d, y, HH:mm');

/// "Nov 20, 2026, 18:42".
String fullTimeLabel(DateTime? at) =>
    at == null ? 'Pending' : _fullTime.format(at.toLocal());

/// What the app sent along, as the message's foot line: "From Profile ·
/// App 1.0.0 (12) · iOS 18.1 · iPhone 15 · en-GB · user ", the uid after it.
/// Empty details are left out.
String threadDetailsLabel(SupportThread thread) {
  final version = thread.appVersion.split('+');
  final platform = switch (thread.platform) {
    'ios' => 'iOS',
    'android' => 'Android',
    final other => other,
  };
  return [
    if (thread.source.isNotEmpty)
      'From ${thread.source[0].toUpperCase()}${thread.source.substring(1)}',
    if (thread.appVersion.isNotEmpty)
      version.length == 2
          ? 'App ${version[0]} (${version[1]})'
          : 'App ${thread.appVersion}',
    if ('$platform ${thread.osVersion}'.trim() case final os when os.isNotEmpty)
      os,
    if (thread.deviceModel.isNotEmpty) thread.deviceModel,
    if (thread.locale.isNotEmpty) thread.locale,
    'user ',
  ].join(' · ');
}

/// What the inbox says about a failed send, close or reopen.
String supportFailureMessage(Failure failure) => switch (failure) {
  RepliesUnavailableFailure() =>
    'Replies cannot be sent: the sendSupportReply function is not deployed '
        'to this project.',
  ReplyInProgressFailure() =>
    'This reply is already being sent. If it does not show as sent in a few '
        'minutes, it may not have gone out.',
  ReplyNotSentFailure() => 'Gmail did not take the reply. Nothing was sent.',
  ReplyOutcomeUnknownFailure() =>
    'The reply may or may not have been sent. It will not be sent again.',
  NotFoundFailure() => 'This thread no longer exists.',
  ValidationFailure(:final message) => 'Not sent: $message',
  _ => failureMessage(failure),
};
