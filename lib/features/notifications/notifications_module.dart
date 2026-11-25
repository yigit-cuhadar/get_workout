import 'package:forge_core/forge_core.dart';
import 'package:forge_messaging/forge_messaging.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';
import '../programs/presentation/program_text.dart';
import '../settings/domain/user_settings.dart';
import '../settings/presentation/app_language.dart';
import 'data/device_notification_repository.dart';
import 'data/notification_payloads.dart';
import 'data/notifications_asked_marker.dart';
import 'domain/notification_repository.dart';
import 'domain/notifications_usecases.dart';
import 'domain/reminder_plan.dart';
import 'presentation/notifications_cubit.dart';

/// Registers local notifications, initialised once in the background
/// (`sl.getAsync<Notifications>()` waits for that), which creates the
/// Android channels before any pushed message can need them, the
/// reminders and the
/// announcements (forge_messaging, which also gives `DevicesModule` its
/// push tokens). Not for the admin panel. Needs `AuthModule`,
/// `SettingsModule`, `ProgramsModule` (programs and Premium) and
/// `BodyModule` (measurement days).
class NotificationsModule implements FeatureModule {
  const NotificationsModule();

  /// The local notification an announcement shows in front of the app; a
  /// newer one replaces it.
  static const _announcementNotificationId = 300;

  @override
  void register(GetIt sl) {
    final taps = NotificationTaps();
    sl
      ..registerSingleton(taps)
      ..registerSingletonAsync<Notifications>(() async {
        // At start, before any user's settings: the phone's language.
        final l10n = localizationsIn(AppLanguage.automatic);
        final notifications = LocalNotifications(
          channel: NotificationChannel(
            id: 'workout',
            name: l10n.notificationChannelName,
            description: l10n.notificationChannelDescription,
            importance: Importance.high,
          ),
          // The workout in progress and its rests on the lock screen; its
          // id is from when it showed rests only. Default importance: lower
          // ones may be hidden there. Silent, unlike `workout`.
          countdownChannel: NotificationChannel(
            id: 'rest',
            name: l10n.lockScreenChannelName,
            description: l10n.lockScreenChannelDescription,
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
        () => DeviceNotificationRepository(sl.getAsync<Notifications>(), sl()),
      )
      ..registerLazySingleton(
        () => const NotificationsAskedMarker(getApplicationSupportDirectory),
      )
      ..registerFactory(() => GetNotificationAccess(sl()))
      ..registerFactory(() => RequestNotificationAccess(sl()))
      ..registerFactory(() => GetNotificationsAsked(sl()))
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
          watchPremium: sl(),
          planWorkout: const PlanWorkoutReminders(),
          planMeasurement: const PlanMeasurementReminders(),
          sync: sl(),
          getAccess: sl(),
          requestAccess: sl(),
          getAsked: sl(),
          openSettings: sl(),
          refreshTimeZone: sl(),
          followAnnouncements: sl(),
          workoutText: (reminder, language) {
            final l10n = localizationsIn(language);
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
          measurementText: (language) {
            final l10n = localizationsIn(language);
            return (
              title: l10n.measurementReminderTitle,
              body: l10n.measurementReminderBody,
            );
          },
          language: (language) => localizationsIn(language).localeName,
        ),
      );
    MessagingModule(
      topics: LanguageTopics(
        AnnouncementTopics.prefix,
        languages: [
          for (final locale in AppLocalizations.supportedLocales)
            locale.toString(),
        ],
        segments: const [AnnouncementTopics.free, AnnouncementTopics.premium],
      ),
      notificationId: _announcementNotificationId,
      tapPayload: NotificationPayloads.announcement,
    ).register(sl);
  }
}
