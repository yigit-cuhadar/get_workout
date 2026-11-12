import 'package:forge_core/forge_core.dart';

import 'reminder_plan.dart';

/// A notification to have pending, with its text.
typedef ReminderNotice = ({int id, DateTime at, String title, String body});

/// The device's local notifications as reminders use them.
abstract interface class NotificationRepository {
  /// Whether the device lets the app notify.
  Future<Result<bool>> allowed();

  /// Asks the device to let the app notify; whether it may.
  Future<Result<bool>> request();

  /// Opens the system settings of the app's notifications.
  Future<Result<void>> openSettings();

  /// Follows a device time zone change.
  Future<Result<void>> refreshTimeZone();

  /// Makes the pending reminders of [kind] exactly [wanted]: schedules what
  /// is missing or differs, cancels the rest of that kind, and leaves equal
  /// ones alone. Every notice is tried; the last failure is returned.
  Future<Result<void>> syncReminders(
    ReminderKind kind,
    List<ReminderNotice> wanted,
  );
}

/// Announcements, pushed to every device of one language (an FCM topic).
abstract interface class AnnouncementRepository {
  /// Receives the announcements in [language] on this device from now on,
  /// and no longer those of any other. Without a push token (no APNs or
  /// Play services) it does nothing and succeeds.
  Future<Result<void>> follow(String language);
}
