import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../../app/functions_region.dart';
import '../domain/account_repository.dart';

/// Deletes through the callable Cloud Function `deleteAccount` (SPEC's
/// Cloud Functions), which removes the user's documents, photos and sign-in
/// with admin rights; the client could not delete Storage folders or other
/// devices' data on its own.
class CallableAccountRepository implements AccountRepository {
  const CallableAccountRepository(
    this._functions,
    this._auth,
    this._firestore, {
    this.pendingWritesWait = const Duration(seconds: 10),
  });

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// How long the device's pending writes may take to reach the server;
  /// longer means offline.
  final Duration pendingWritesWait;

  /// Where the functions are deployed.
  static const region = functionsRegion;
  static const function = 'deleteAccount';

  /// `details.reason` values of the function's refusals
  /// (`functions/src/delete_account.ts`).
  static const _recentSignIn = 'recent-sign-in';
  static const _signInNotDeleted = 'sign-in-not-deleted';

  @override
  Future<Result<void>> deleteAccount() => guard(() async {
    // A write queued now would land after the deletion and bring data back.
    try {
      await _firestore.waitForPendingWrites().timeout(pendingWritesWait);
    } on TimeoutException catch (error) {
      throw NetworkFailure('pending writes not sent', error);
    }
    await _functions.httpsCallable(function).call<void>();
  }, mapper: _mapError);

  @override
  Future<Result<void>> reauthenticate(String password) => guard(() async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthFailure('no email user signed in');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> signOut() =>
      guard(_auth.signOut, mapper: mapFirebaseError);

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch ((error.code, reason)) {
      (_, _recentSignIn) => AuthFailure(
        error.message ?? error.code,
        code: recentLoginRequiredCode,
        cause: error,
      ),
      (_, _signInNotDeleted) => PartlyDeletedFailure(
        error.message ?? error.code,
        error,
      ),
      // Not deployed (404), or deployed without permission to call it.
      ('not-found' || 'permission-denied', _) => DeletionUnavailableFailure(
        error.message ?? error.code,
        error,
      ),
      _ => mapFirebaseError(error),
    };
  }
}
