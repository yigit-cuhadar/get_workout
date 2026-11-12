import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/notifications/data/device_notification_repository.dart';
import 'package:get_workout/features/notifications/data/notification_taps.dart';
import 'package:get_workout/features/notifications/domain/notification_repository.dart';
import 'package:get_workout/features/notifications/domain/reminder_plan.dart';
import 'package:mocktail/mocktail.dart';

class MockNotifications extends Mock implements Notifications {}

void main() {
  late MockNotifications notifications;
  late List<PendingNotification> pending;
  late DeviceNotificationRepository repository;

  ReminderNotice notice(int id, {int day = 13, String body = 'Upper'}) => (
    id: id,
    at: DateTime(2026, 11, day, 8),
    title: 'Workout today',
    body: body,
  );

  PendingNotification pendingOf(ReminderKind kind, ReminderNotice notice) =>
      PendingNotification(
        notice.id,
        NotificationPayloads.reminder(kind, notice),
      );

  setUpAll(() => registerFallbackValue(DateTime(2000)));

  setUp(() {
    notifications = MockNotifications();
    pending = [];
    when(notifications.pending).thenAnswer((_) async => Ok(pending));
    when(() => notifications.cancel(any()))
        .thenAnswer((_) async => const Ok(null));
    when(
      () => notifications.scheduleAt(
        any(),
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    repository = DeviceNotificationRepository(Future.value(notifications));
  });

  test('schedules what is missing with a reminder payload', () async {
    final wanted = notice(105);

    final result = await repository.syncReminders(ReminderKind.workout, [
      wanted,
    ]);

    expect(result.isOk, isTrue);
    verify(
      () => notifications.scheduleAt(
        105,
        wanted.at,
        title: 'Workout today',
        body: 'Upper',
        payload: NotificationPayloads.reminder(ReminderKind.workout, wanted),
      ),
    ).called(1);
    verifyNever(() => notifications.cancel(any()));
  });

  test('leaves an equal one alone and replaces a changed one', () async {
    final same = notice(105);
    final moved = notice(106, day: 14);
    final renamed = notice(107, body: 'Lower');
    pending = [
      pendingOf(ReminderKind.workout, same),
      pendingOf(ReminderKind.workout, notice(106, day: 15)),
      pendingOf(ReminderKind.workout, notice(107)),
    ];

    await repository.syncReminders(ReminderKind.workout, [
      same,
      moved,
      renamed,
    ]);

    verifyNever(
      () => notifications.scheduleAt(
        105,
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    );
    for (final id in [106, 107]) {
      verify(
        () => notifications.scheduleAt(
          id,
          any(),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).called(1);
    }
    verifyNever(() => notifications.cancel(any()));
  });

  test('cancels only the unwanted ones of its own kind', () async {
    pending = [
      pendingOf(ReminderKind.workout, notice(105)),
      pendingOf(ReminderKind.measurement, notice(200)),
      // The rest notification.
      const PendingNotification(1, null),
    ];

    await repository.syncReminders(ReminderKind.workout, const []);

    verify(() => notifications.cancel(105)).called(1);
    verifyNever(() => notifications.cancel(200));
    verifyNever(() => notifications.cancel(1));
  });

  test('tries every notice and returns the last failure', () async {
    const failure = ValidationFailure('in the past');
    when(
      () => notifications.scheduleAt(
        105,
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const Err(failure));

    final result = await repository.syncReminders(ReminderKind.workout, [
      notice(105),
      notice(106, day: 14),
    ]);

    expect(result.failureOrNull, failure);
    verify(
      () => notifications.scheduleAt(
        106,
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    ).called(1);
  });

  test('a failure to read the pending ones changes nothing', () async {
    const failure = UnknownFailure('not ready');
    when(notifications.pending).thenAnswer((_) async => const Err(failure));

    final result = await repository.syncReminders(ReminderKind.workout, [
      notice(105),
    ]);

    expect(result.failureOrNull, failure);
    verifyNever(
      () => notifications.scheduleAt(
        any(),
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    );
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
    final failing = DeviceNotificationRepository(
      Future.value(notifications),
      openSystemSettings: () async => throw const UnknownFailure('no'),
    );

    expect((await failing.openSettings()).isOk, isFalse);
  });

  group('taps', () {
    test('payloads name their target', () {
      expect(
        NotificationPayloads.targetOf(
          NotificationPayloads.reminder(ReminderKind.workout, notice(105)),
        ),
        NotificationTarget.workout,
      );
      expect(
        NotificationPayloads.targetOf(
          NotificationPayloads.reminder(ReminderKind.measurement, notice(200)),
        ),
        NotificationTarget.measurement,
      );
      expect(
        NotificationPayloads.targetOf(NotificationPayloads.announcement),
        NotificationTarget.announcement,
      );
      expect(NotificationPayloads.targetOf(null), isNull);
      expect(NotificationPayloads.targetOf('reminder:other:1:2'), isNull);
    });

    test('a tap before anyone listens reaches the first listener', () {
      final taps = NotificationTaps()
        ..add(null)
        ..add(NotificationPayloads.announcement);
      final heard = <NotificationTarget>[];

      taps.listen(heard.add);
      taps.add(NotificationPayloads.reminder(ReminderKind.workout, notice(1)));

      expect(heard, [
        NotificationTarget.announcement,
        NotificationTarget.workout,
      ]);
    });
  });
}
