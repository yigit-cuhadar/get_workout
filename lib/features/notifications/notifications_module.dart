import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';

import '../../core/device_localizations.dart';
import '../../l10n/app_localizations.dart';
import '../programs/presentation/program_text.dart';
import 'data/device_notification_repository.dart';
import 'data/fcm_announcement_repository.dart';
import 'domain/notification_repository.dart';
import 'domain/notifications_usecases.dart';
import 'domain/reminder_plan.dart';
import 'presentation/notifications_cubit.dart';

/// Registers local notifications, initialised once in the background
/// (`sl.getAsync<Notifications>()` waits for that), which creates the
/// Android channels before any pushed message can need them, the
/// reminders and the
/// announcements. Not for the admin panel. Needs `AuthModule`,
/// `SettingsModule`, `ProgramsModule` and `BodyModule` (measurement days).
class NotificationsModule implements FeatureModule {
  const NotificationsModule();

  @override
  void register(GetIt sl) {
    final taps = NotificationTaps();
    sl
      ..registerSingleton(taps)
      ..registerSingletonAsync<Notifications>(() async {
        final l10n = deviceLocalizations();
        final notifications = LocalNotifications(
          channel: NotificationChannel(
            id: 'workout',
            name: l10n.notificationChannelName,
            description: l10n.notificationChannelDescription,
            importance: Importance.high,
          ),
          // The running rest on the lock screen. Default importance: lower
          // ones may be hidden there. Silent, unlike `workout`.
          countdownChannel: NotificationChannel(
            id: 'rest',
            name: l10n.restChannelName,
            description: l10n.restChannelDescription,
            importance: Importance.defaultImportance,
          ),
          androidIcon: 'ic_notification',
        );
        // On failure every call fails and is logged by its caller; the app
        // works on without notifications.
        final init = await notifications.init(onTap: taps.add);
        if (init.failureOrNull case final failure?) {
          Log.e('notifications', 'init failed: ${failure.message}');
        }
        return notifications;
      })
      ..registerLazySingleton<NotificationRepository>(
        () => DeviceNotificationRepository(sl.getAsync<Notifications>()),
      )
      ..registerLazySingleton<AnnouncementRepository>(
        () => FcmAnnouncementRepository(
          FirebaseMessaging.instance,
          languages: [
            for (final locale in AppLocalizations.supportedLocales)
              locale.toString(),
          ],
          onMessage: FirebaseMessaging.onMessage,
          onMessageOpenedApp: FirebaseMessaging.onMessageOpenedApp,
          notifications: sl.getAsync<Notifications>(),
          taps: taps,
        ),
      )
      ..registerFactory(() => GetNotificationAccess(sl()))
      ..registerFactory(() => RequestNotificationAccess(sl()))
      ..registerFactory(() => OpenNotificationSettings(sl()))
      ..registerFactory(() => RefreshTimeZone(sl()))
      ..registerFactory(() => SyncReminders(sl()))
      ..registerFactory(() => FollowAnnouncements(sl()))
      // One for the whole app, created at start so reminders follow from
      // the first user on.
      ..registerLazySingleton(
        () => NotificationsCubit(
          watchAuthUser: sl(),
          watchSettings: sl(),
          watchMeasured: sl(),
          programs: sl(),
          planWorkout: const PlanWorkoutReminders(),
          planMeasurement: const PlanMeasurementReminders(),
          sync: sl(),
          getAccess: sl(),
          requestAccess: sl(),
          openSettings: sl(),
          refreshTimeZone: sl(),
          followAnnouncements: sl(),
          workoutText: (reminder) {
            final l10n = deviceLocalizations();
            final day = reminder.day;
            return (
              title: l10n.workoutReminderTitle,
              body: day == null
                  ? reminder.programName
                  : l10n.workoutReminderDay(
                      l10n.dayName(day.day, day.index),
                      reminder.programName,
                    ),
            );
          },
          measurementText: () {
            final l10n = deviceLocalizations();
            return (
              title: l10n.measurementReminderTitle,
              body: l10n.measurementReminderBody,
            );
          },
          language: () => deviceLocalizations().localeName,
        ),
      );
  }
}
