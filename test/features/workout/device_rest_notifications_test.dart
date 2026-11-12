import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/workout/data/device_rest_notifications.dart';
import 'package:mocktail/mocktail.dart';

class MockNotifications extends Mock implements Notifications {}

void main() {
  late MockNotifications notifications;
  late Directory directory;
  late DeviceRestNotifications rest;
  const id = DeviceRestNotifications.id;

  setUpAll(() => registerFallbackValue(DateTime(2000)));

  setUp(() {
    notifications = MockNotifications();
    directory = Directory.systemTemp.createTempSync('rest_notifications');
    rest = DeviceRestNotifications(
      Future.value(notifications),
      () async => directory,
    );
    when(notifications.requestExact).thenAnswer((_) async => const Ok(true));
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('allowed reads the device permission', () async {
    when(notifications.status)
        .thenAnswer((_) async => const Ok(NotificationPermission.denied));
    expect((await rest.allowed()).valueOrNull, isFalse);
  });

  test('a granted request asks for exact alarms when they are off', () async {
    when(notifications.request)
        .thenAnswer((_) async => const Ok(NotificationPermission.granted));
    when(notifications.canScheduleExact)
        .thenAnswer((_) async => const Ok(false));
    expect((await rest.request()).valueOrNull, isTrue);
    verify(notifications.requestExact).called(1);
  });

  test('exact alarms are not asked for when on, nor after a refusal', () async {
    when(notifications.canScheduleExact)
        .thenAnswer((_) async => const Ok(true));
    when(notifications.request)
        .thenAnswer((_) async => const Ok(NotificationPermission.granted));
    await rest.request();
    when(notifications.request)
        .thenAnswer((_) async => const Ok(NotificationPermission.denied));
    expect((await rest.request()).valueOrNull, isFalse);
    verifyNever(notifications.requestExact);
  });

  test('schedule and cancel use the rest notification\'s id', () async {
    final at = DateTime(2026, 11, 11, 18, 2);
    when(
      () => notifications.scheduleAt(
        any(),
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    when(() => notifications.cancel(any()))
        .thenAnswer((_) async => const Ok(null));
    await rest.schedule(at, title: 'Rest over', body: 'Next');
    await rest.cancel();
    verify(
      () => notifications.scheduleAt(id, at, title: 'Rest over', body: 'Next'),
    ).called(1);
    verify(() => notifications.cancel(id)).called(1);
  });

  test('being asked here is remembered on the device', () async {
    expect((await rest.askedHere()).valueOrNull, isFalse);
    expect((await rest.markAskedHere()).isOk, isTrue);
    final again = DeviceRestNotifications(
      Future.value(notifications),
      () async => directory,
    );
    expect((await again.askedHere()).valueOrNull, isTrue);
  });
}
