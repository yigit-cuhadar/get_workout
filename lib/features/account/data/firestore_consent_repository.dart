import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/consent_repository.dart';

/// `settings.analyticsConsent` of `users/{uid}`. The settings feature
/// writes the rest of that map with merges, so neither overwrites the
/// other.
class FirestoreConsentRepository implements ConsentRepository {
  const FirestoreConsentRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<bool?> watchConsent(String uid) => _user(uid)
      .snapshots()
      .map((snap) {
        // Anything but a boolean reads as not answered.
        final settings = snap.data()?['settings'];
        return settings is Map && settings['analyticsConsent'] is bool
            ? settings['analyticsConsent'] as bool
            : null;
      })
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('consent', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );

  @override
  Future<Result<void>> saveConsent(String uid, bool consent) => guard(
    () => _user(uid).set({
      'settings': {'analyticsConsent': consent},
    }, SetOptions(merge: true)),
    mapper: mapFirebaseError,
  );

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);
}
