import 'package:forge_core/forge_core.dart';

/// [AuthFailure.code] when the server wants a recent sign-in before it
/// deletes an account; the user enters their password ([reauthenticate])
/// and tries again. Firebase's own code for the same rule.
const recentLoginRequiredCode = 'requires-recent-login';

/// The server cannot delete accounts: the `deleteAccount` function is not
/// deployed. Nothing was deleted.
final class DeletionUnavailableFailure extends Failure {
  const DeletionUnavailableFailure([
    super.message = 'deleteAccount is not deployed',
    Object? cause,
  ]) : super(cause: cause);
}

/// The signed-in user's account on the server.
abstract interface class AccountRepository {
  /// Deletes the signed-in user's stored data, photos and sign-in, guests
  /// included. Fails with [DeletionUnavailableFailure] while the server
  /// cannot, and with [recentLoginRequiredCode] when the sign-in is too old.
  Future<Result<void>> deleteAccount();

  /// Signs the email user in again with [password], so the sign-in is
  /// recent.
  Future<Result<void>> reauthenticate(String password);
}

/// What this device keeps for a user outside Firestore.
abstract interface class LocalAccountData {
  Future<Result<void>> clear(String uid);
}
