import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/notifications/data/device_notification_repository.dart';
import 'package:get_workout/features/notifications/data/notification_payloads.dart';
import 'package:get_workout/features/notifications/domain/notification_repository.dart';
import 'package:get_workout/features/notifications/domain/reminder_plan.dart';
import 'package:mocktail/mocktail.dart';

class MockNotifications extends Mock implements Notifications {}

void main() {
  late MockNotifications notifications;
  late DeviceNotificationRepository repository;

  ReminderNotice notice(int id, {int day = 13}) => (
    id: id,
    at: DateTime(2026, 11, day, 8),
    title: 'Workout today',
    body: 'Upper',
  );

  void syncAnswers(Result<void> result) => when(
    () => notifications.sync(
      any(),
      count: any(named: 'count'),
      wanted: any(named: 'wanted'),
    ),
  ).thenAnswer((_) async => result);

  setUp(() {
    notifications = MockNotifications();
    syncAnswers(const Ok(null));
    repository = DeviceNotificationRepository(Future.value(notifications));
  });

  test('syncs the ids of its kind to the notices', () async {
    final result = await repository.syncReminders(ReminderKind.workout, [
      notice(105),
      notice(106, day: 14),
    ]);

    expect(result.isOk, isTrue);
    final payload = NotificationPayloads.reminder(ReminderKind.workout);
    verify(
      () => notifications.sync(
        ReminderIds.workoutBase,
        count: ReminderIds.workoutDays,
        wanted: [
          OneOffNotification(
            105,
            DateTime(2026, 11, 13, 8),
            title: 'Workout today',
            body: 'Upper',
            payload: payload,
          ),
          OneOffNotification(
            106,
            DateTime(2026, 11, 14, 8),
            title: 'Workout today',
            body: 'Upper',
            payload: payload,
          ),
        ],
      ),
    ).called(1);
  });

  test('measurement reminders own their own ids', () async {
    await repository.syncReminders(ReminderKind.measurement, const []);

    verify(
      () => notifications.sync(
        ReminderIds.measurementBase,
        count: ReminderIds.measurementCount,
        wanted: const [],
      ),
    ).called(1);
  });

  test('a failed sync is returned', () async {
    const failure = ValidationFailure('in the past');
    syncAnswers(const Err(failure));

    final result = await repository.syncReminders(ReminderKind.workout, [
      notice(105),
    ]);

    expect(result.failureOrNull, failure);
  });

  test('access is whether the device grants it', () async {
    when(notifications.status)
        .thenAnswer((_) async => const Ok(NotificationPermission.denied));
    when(notifications.request)
        .thenAnswer((_) async => const Ok(NotificationPermission.granted));

    expect((await repository.allowed()).valueOrNull, isFalse);
    expect((await repository.request()).valueOrNull, isTrue);
  });

  test('settings that do not open are a failure', () async {
    when(notifications.openSettings)
        .thenAnswer((_) async => const Err(UnknownFailure('no')));

    expect((await repository.openSettings()).isOk, isFalse);
  });

  test('payloads name their target', () {
    expect(
      NotificationPayloads.targetOf(
        NotificationPayloads.reminder(ReminderKind.workout),
      ),
      NotificationTarget.workout,
    );
    expect(
      NotificationPayloads.targetOf(
        NotificationPayloads.reminder(ReminderKind.measurement),
      ),
      NotificationTarget.measurement,
    );
    expect(
      NotificationPayloads.targetOf(NotificationPayloads.announcement),
      NotificationTarget.announcement,
    );
    // Scheduled by an earlier version, with time and text hash.
    expect(
      NotificationPayloads.targetOf('reminder:measurement:1794643200000:1a2b'),
      NotificationTarget.measurement,
    );
    expect(NotificationPayloads.targetOf(null), isNull);
    expect(NotificationPayloads.targetOf('reminder:other:1:2'), isNull);
    // Opened like the iOS Live Activity, not as a target.
    expect(
      NotificationPayloads.targetOf(NotificationPayloads.activeWorkout),
      isNull,
    );
  });
}
