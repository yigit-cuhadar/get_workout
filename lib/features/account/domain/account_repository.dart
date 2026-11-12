import 'package:forge_core/forge_core.dart';

/// [AuthFailure.code] when the server wants a recent sign-in before it
/// deletes an account; the user enters their password ([reauthenticate])
/// and tries again. Firebase's own code for the same rule.
const recentLoginRequiredCode = 'requires-recent-login';

/// The server cannot delete accounts: the `deleteAccount` function is not
/// deployed or cannot be called. Nothing was deleted.
final class DeletionUnavailableFailure extends Failure {
  const DeletionUnavailableFailure([
    super.message = 'deleteAccount cannot be called',
    Object? cause,
  ]) : super(cause: cause);
}

/// The server deleted the data but not the sign-in; deleting again
/// finishes it. Until then the user must not carry on with the account.
final class PartlyDeletedFailure extends Failure {
  const PartlyDeletedFailure([
    super.message = 'sign-in not deleted',
    Object? cause,
  ]) : super(cause: cause);
}

/// The signed-in user's account on the server.
abstract interface class AccountRepository {
  /// Sends this device's pending writes first, failing with
  /// [NetworkFailure] when they cannot go (offline) and nothing was asked;
  /// then deletes the signed-in user's stored data, photos and sign-in,
  /// guests included. Fails with [DeletionUnavailableFailure] while the
  /// server cannot, [recentLoginRequiredCode] when the sign-in is too old
  /// and [PartlyDeletedFailure] when only the sign-in is left.
  Future<Result<void>> deleteAccount();

  /// Signs the email user in again with [password], so the sign-in is
  /// recent.
  Future<Result<void>> reauthenticate(String password);

  /// Ends the session on this device.
  Future<Result<void>> signOut();
}

/// What this device keeps for a user outside the server.
abstract interface class LocalAccountData {
  /// Stops sending [uid]'s data from this device (their photo backup), so
  /// nothing reaches the server after it deleted their account.
  Future<void> holdWrites(String uid);

  /// Undoes [holdWrites]: the account was not deleted.
  Future<void> releaseWrites(String uid);

  /// Removes it now, and the offline copy of the server data at the next
  /// start, before it is used.
  Future<Result<void>> clear(String uid);
}
