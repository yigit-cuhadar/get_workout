import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/account_repository.dart';

/// Deletes through the callable Cloud Function `deleteAccount` (SPEC's
/// Cloud Functions), which removes the user's documents, photos and sign-in
/// with admin rights; the client could not delete Storage folders or other
/// devices' data on its own.
class CallableAccountRepository implements AccountRepository {
  const CallableAccountRepository(this._functions, this._auth);

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// Where the functions are deployed, next to Firestore's `eur3`.
  static const region = 'europe-west1';
  static const function = 'deleteAccount';

  @override
  Future<Result<void>> deleteAccount() => guard(() async {
    await _functions.httpsCallable(function).call<void>();
    // The sign-in is gone on the server; end it here too.
    await _auth.signOut();
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

  static Failure? _mapError(Object error) => switch (error) {
    // A callable that is not deployed answers 404.
    FirebaseFunctionsException(code: 'not-found') => DeletionUnavailableFailure(
      error.message ?? error.code,
      error,
    ),
    FirebaseFunctionsException(
      code: 'failed-precondition',
      message: recentLoginRequiredCode,
    ) =>
      AuthFailure(
        recentLoginRequiredCode,
        code: recentLoginRequiredCode,
        cause: error,
      ),
    _ => mapFirebaseError(error),
  };
}
