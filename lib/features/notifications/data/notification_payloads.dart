import '../domain/reminder_plan.dart';

/// What a tapped notification opens.
enum NotificationTarget { workout, measurement, announcement }

/// The payloads of the app's notifications.
abstract final class NotificationPayloads {
  static const announcement = 'announcement';
  static const _reminder = 'reminder';

  static String reminder(ReminderKind kind) => '$_reminder:${kind.name}';

  /// Null for the rest notification, which has none, and anything unknown.
  /// Reminders scheduled before the payload lost its time and text hash
  /// (`reminder:<kind>:…`) still parse.
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

  /// The targets of tapped notifications' [payloads], without the taps
  /// that have none (the rest notification) or an unknown one.
  static Stream<NotificationTarget> targetsOf(Stream<String?> payloads) =>
      payloads.map(targetOf).where((target) => target != null).cast();
}
