import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/notifications/data/fcm_announcement_repository.dart';
import 'package:get_workout/features/notifications/data/notification_payloads.dart';
import 'package:mocktail/mocktail.dart';

class MockMessaging extends Mock implements FirebaseMessaging {}

class MockNotifications extends Mock implements Notifications {}

void main() {
  late MockMessaging messaging;
  late MockNotifications notifications;
  late StreamController<RemoteMessage> messages;
  late StreamController<RemoteMessage> opened;
  late NotificationTaps taps;
  late List<String?> tapped;
  late FcmAnnouncementRepository repository;

  setUp(() {
    messaging = MockMessaging();
    notifications = MockNotifications();
    messages = StreamController();
    opened = StreamController();
    taps = NotificationTaps();
    tapped = [];
    taps.stream.listen(tapped.add);
    when(() => messaging.getInitialMessage()).thenAnswer((_) async => null);
    when(() => messaging.getAPNSToken()).thenAnswer((_) async => null);
    when(() => messaging.setAutoInitEnabled(any())).thenAnswer((_) async {});
    when(() => messaging.subscribeToTopic(any())).thenAnswer((_) async {});
    when(() => messaging.unsubscribeFromTopic(any())).thenAnswer((_) async {});
    when(
      () => notifications.show(
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    repository = FcmAnnouncementRepository(
      messaging,
      languages: const ['en', 'de'],
      onMessage: messages.stream,
      onMessageOpenedApp: opened.stream,
      notifications: Future.value(notifications),
      taps: taps,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    unawaited(messages.close());
    unawaited(opened.close());
  });

  test('follows its language and leaves the others', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final result = await repository.follow('en');

    expect(result.isOk, isTrue);
    verify(() => messaging.unsubscribeFromTopic('announcements_de')).called(1);
    verify(() => messaging.subscribeToTopic('announcements_en')).called(1);
    verifyNever(() => messaging.unsubscribeFromTopic('announcements_en'));
  });

  test('turns on push tokens before following', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await repository.follow('en');

    verifyInOrder([
      () => messaging.setAutoInitEnabled(true),
      () => messaging.subscribeToTopic('announcements_en'),
    ]);
  });

  test('on iOS without an APNs token it quietly follows nothing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final result = await repository.follow('en');

    expect(result.isOk, isTrue);
    verifyNever(() => messaging.subscribeToTopic(any()));
  });

  test('on iOS with an APNs token it follows', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    when(() => messaging.getAPNSToken()).thenAnswer((_) async => 'apns');

    await repository.follow('en');

    verify(() => messaging.subscribeToTopic('announcements_en')).called(1);
  });

  test('a failed subscription is a failure', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    when(() => messaging.subscribeToTopic(any()))
        .thenThrow(Exception('no Play services'));

    expect((await repository.follow('en')).isOk, isFalse);
  });

  test('shows an announcement arriving in front of the app', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await repository.follow('en');

    messages
      ..add(
        const RemoteMessage(
          notification: RemoteNotification(title: 'New', body: 'Programs'),
        ),
      )
      ..add(const RemoteMessage(data: {'silent': 'yes'}));
    await pumpEventQueue();

    verify(
      () => notifications.show(
        FcmAnnouncementRepository.notificationId,
        title: 'New',
        body: 'Programs',
        payload: NotificationPayloads.announcement,
      ),
    ).called(1);
  });

  test('reports taps, including the one that launched the app', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    when(() => messaging.getInitialMessage())
        .thenAnswer((_) async => const RemoteMessage());

    await repository.follow('en');
    opened.add(const RemoteMessage());
    await pumpEventQueue();

    expect(tapped, [
      NotificationPayloads.announcement,
      NotificationPayloads.announcement,
    ]);
  });

  test('listens once however often it follows', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await repository.follow('en');
    await repository.follow('de');

    verify(() => messaging.getInitialMessage()).called(1);
  });
}
