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

  /// Whether this device was asked to let the app notify, by the reminders
  /// or the rest notification; until then [allowed] reads false too.
  Future<Result<bool>> askedHere();

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

/// Which announcements a device takes: those of its [language], and of
/// the user's Premium state ([premium]; null while unknown).
typedef AnnouncementAudience = ({String language, bool? premium});

/// Announcements, pushed to the devices of one language, to all of them or
/// to the free or the Premium ones (FCM topics).
abstract interface class AnnouncementRepository {
  /// Receives [audience]'s announcements on this device from now on: its
  /// language's for everyone, and once the Premium state is known, the
  /// free or the Premium ones, leaving the other and every other
  /// language's. Without a push token (no APNs or Play services) it does
  /// nothing and succeeds.
  Future<Result<void>> follow(AnnouncementAudience audience);
}
