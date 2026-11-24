import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/notification_repository.dart';
import 'notification_payloads.dart';

/// [AnnouncementRepository] over FCM topics: `announcements_<language>`
/// for everyone, and `announcements_<language>_free` or `_premium` for the
/// user's Premium state (`functions/src/send_announcement.ts`).
/// Announcements arrive as notification messages: the system shows them
/// while the app is in the background; in front, the app shows them as a
/// local notification. Taps on either go to [_taps].
class FcmAnnouncementRepository implements AnnouncementRepository {
  FcmAnnouncementRepository(
    this._messaging, {
    required this._languages,
    required this._onMessage,
    required Stream<RemoteMessage> onMessageOpenedApp,
    required this._notifications,
    required this._taps,
  }) : _onOpened = onMessageOpenedApp;

  final FirebaseMessaging _messaging;

  /// Every language the app has, so a device leaves the others' topics.
  final List<String> _languages;
  final Stream<RemoteMessage> _onMessage;
  final Stream<RemoteMessage> _onOpened;
  final Future<Notifications> _notifications;
  final NotificationTaps _taps;
  var _listening = false;

  /// The local notification an announcement shows in front of the app;
  /// a newer one replaces it.
  static const notificationId = 300;

  /// The topic of everyone in [language], or with [premium] of its free or
  /// its Premium users only.
  static String topic(String language, {bool? premium}) => switch (premium) {
    null => 'announcements_$language',
    false => 'announcements_${language}_free',
    true => 'announcements_${language}_premium',
  };

  @override
  Future<Result<void>> follow(AnnouncementAudience audience) => guard(() async {
    await _listen();
    // Off in the native config, so devices that never allow notifications
    // get no push token.
    await _messaging.setAutoInitEnabled(true);
    if (!await _hasToken()) return;
    final (:language, :premium) = audience;
    for (final other in _languages) {
      if (other == language) continue;
      for (final tier in const [null, false, true]) {
        await _messaging.unsubscribeFromTopic(topic(other, premium: tier));
      }
    }
    await _messaging.subscribeToTopic(topic(language));
    // While the Premium state is unknown the device keeps its tier topic.
    if (premium != null) {
      await _messaging.unsubscribeFromTopic(topic(language, premium: !premium));
      await _messaging.subscribeToTopic(topic(language, premium: premium));
    }
  }, mapper: mapFirebaseError);

  Future<void> _listen() async {
    if (_listening) return;
    _listening = true;
    _onMessage.listen(_show);
    _onOpened.listen((_) => _taps.add(NotificationPayloads.announcement));
    if (await _messaging.getInitialMessage() != null) {
      _taps.add(NotificationPayloads.announcement);
    }
  }

  /// iOS has no push token without APNs (needing the Apple Developer
  /// account), and topics cannot be followed without one. Android without
  /// Play services fails to subscribe instead, and is tried again later.
  Future<bool> _hasToken() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    if (await _messaging.getAPNSToken() != null) return true;
    Log.d('announcements', 'no APNs token; announcements not followed');
    return false;
  }

  Future<void> _show(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title;
    final body = notification?.body;
    if (title == null && body == null) return;
    final result = await (await _notifications).show(
      notificationId,
      title: title ?? '',
      body: body ?? '',
      payload: NotificationPayloads.announcement,
    );
    if (result.failureOrNull case final failure?) {
      Log.e('announcements', 'not shown: ${failure.message}');
    }
  }
}
