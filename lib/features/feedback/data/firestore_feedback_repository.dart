import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/feedback.dart';
import '../domain/feedback_repository.dart';
import '../../../core/device_details.dart';

/// Messages live in `users/{uid}/feedback/{id}`, so deleting the account
/// deletes them; the admin panel reads them across users.
class FirestoreFeedbackRepository implements FeedbackRepository {
  const FirestoreFeedbackRepository(this._firestore, this._device);

  final FirebaseFirestore _firestore;
  final DeviceDetailsSource _device;

  /// The longest device detail firestore.rules accepts.
  static const maxDetail = 100;

  @override
  Future<Result<void>> send(String uid, FeedbackDraft draft) => guard(() async {
    DeviceDetails device;
    try {
      device = await _device.read();
    } catch (error, stack) {
      // A message without the device is still worth sending.
      Log.e('feedback', 'device details unreadable', error, stack);
      device = const DeviceDetails();
    }
    final write = _firestore
        .collection('users/$uid/feedback')
        .doc()
        .set(toMap(uid, draft, device));
    // Firestore completes a write only when the server confirms, which
    // never happens offline, so the user does not wait for that. The rules
    // check what the draft already checked, so a refusal is only logged.
    unawaited(
      write.then(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            Log.e('feedback', 'message rejected', error, stack),
      ),
    );
  }, mapper: mapFirebaseError);

  static Map<String, Object?> toMap(
    String uid,
    FeedbackDraft draft,
    DeviceDetails device,
  ) {
    String cut(String text) => text.substring(0, min(text.length, maxDetail));
    return {
      'uid': uid,
      if (draft.email.isNotEmpty) 'email': draft.email,
      'message': draft.message,
      'source': draft.source.name,
      'appVersion': cut(device.appVersion),
      'platform': cut(device.platform),
      'osVersion': cut(device.osVersion),
      'deviceModel': cut(device.deviceModel),
      'locale': cut(device.locale),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
