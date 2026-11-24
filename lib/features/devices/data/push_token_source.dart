import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';

/// This install's FCM registration token, which the panel's test
/// announcements are sent to.
abstract interface class PushTokenSource {
  /// The token; null while the install has none.
  Future<String?> read();

  /// Fires when FCM issues a new token.
  Stream<void> changes();
}

/// [PushTokenSource] over [FirebaseMessaging]. FCM auto-init is off until
/// notifications are allowed (`FcmAnnouncementRepository`), so an install
/// that never allowed them has no token and is not given one here.
class MessagingPushTokenSource implements PushTokenSource {
  const MessagingPushTokenSource(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<String?> read() async {
    if (!_messaging.isAutoInitEnabled) return null;
    try {
      // iOS has no token without APNs.
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await _messaging.getAPNSToken() == null) {
        return null;
      }
      // A registration token, which `sendEachForMulticast` takes; the newer
      // installation ids (register, onRegistered) are not used yet.
      // ignore: deprecated_member_use
      return await _messaging.getToken();
    } on Object catch (error) {
      // No Play services, or offline: the device is recorded without one.
      Log.d('devices', 'no push token: $error');
      return null;
    }
  }

  @override
  Stream<void> changes() =>
      // ignore: deprecated_member_use
      _messaging.onTokenRefresh.map((_) {});
}
