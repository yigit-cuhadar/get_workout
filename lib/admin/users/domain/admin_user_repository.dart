import 'package:forge_core/forge_core.dart';

import 'admin_user.dart';

/// The app's users, through the admin-only callables of
/// `functions/src/users/`. Every call fails with [PermissionFailure]
/// without the admin claim and [NetworkFailure] offline.
abstract interface class AdminUserRepository {
  /// Sign-ups newest first, after [after] (from the start when null).
  Future<Result<UsersPage>> latest({UserCursor? after});

  /// The uid of the user whose email (with an `@`) or uid is [query];
  /// [NotFoundFailure] when nobody has it.
  Future<Result<String>> find(String query);

  /// [NotFoundFailure] when the user does not exist.
  Future<Result<UserDetail>> user(String uid);

  /// Grants promotional Premium in RevenueCat; when it ends (null: never).
  /// [RevenueCatFailure] when RevenueCat refuses.
  Future<Result<DateTime?>> grantPremium(String uid, PremiumDuration duration);

  /// Ends promotional Premium in RevenueCat now.
  Future<Result<void>> revokePremium(String uid);

  /// [OwnAccountFailure] on the caller's own account.
  Future<Result<void>> setAdmin(String uid, {required bool admin});

  /// Deletes the account and all of its data; [OwnAccountFailure] on the
  /// caller's own account.
  Future<Result<void>> delete(String uid);
}
