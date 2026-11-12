import '../domain/notification_repository.dart';
import '../domain/reminder_plan.dart';

/// What a tapped notification opens.
enum NotificationTarget { workout, measurement, announcement }

/// The payloads of the app's notifications. A reminder's carries its time
/// and a hash of its text, so an equal pending one is recognised and left.
abstract final class NotificationPayloads {
  static const announcement = 'announcement';
  static const _reminder = 'reminder';

  static String reminder(ReminderKind kind, ReminderNotice notice) =>
      '$_reminder:${kind.name}:${notice.at.millisecondsSinceEpoch}:'
      '${_hash('${notice.title}\n${notice.body}')}';

  /// Null for the rest notification, which has none, and anything unknown.
  static NotificationTarget? targetOf(String? payload) {
    if (payload == announcement) return NotificationTarget.announcement;
    final parts = payload?.split(':') ?? const [];
    if (parts.length < 2 || parts.first != _reminder) return null;
    return switch (ReminderKind.values.asNameMap()[parts[1]]) {
      ReminderKind.workout => NotificationTarget.workout,
      ReminderKind.measurement => NotificationTarget.measurement,
      null => null,
    };
  }

  /// 32-bit FNV-1a: stable across runs, unlike [String.hashCode].
  static String _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}

/// Taps on the app's notifications, local and pushed. A tap that arrives
/// before anyone listens (the one that launched the app) is kept for the
/// first listener.
class NotificationTaps {
  NotificationTarget? _pending;
  void Function(NotificationTarget target)? _listener;

  void add(String? payload) {
    final target = NotificationPayloads.targetOf(payload);
    if (target == null) return;
    final listener = _listener;
    if (listener == null) {
      _pending = target;
    } else {
      listener(target);
    }
  }

  void listen(void Function(NotificationTarget target) listener) {
    _listener = listener;
    final pending = _pending;
    _pending = null;
    if (pending != null) listener(pending);
  }
}
