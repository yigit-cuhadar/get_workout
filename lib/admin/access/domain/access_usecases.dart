import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import 'admin_access_repository.dart';

/// Whether the signed-in user holds the `admin` claim that Firestore rules
/// require for writes to `exercises` (granted by `tool/set_admin.sh`).
class CheckAdminAccess implements UseCase<bool, bool> {
  const CheckAdminAccess(this._repository);
  final AdminAccessRepository _repository;

  /// [params] forces a token refresh.
  @override
  Future<Result<bool>> call(bool params) async =>
      (await _repository.claims(refresh: params)).map(isAdmin);

  /// Only a boolean `true` counts, as in the rules.
  static bool isAdmin(Map<String, Object?> claims) => claims['admin'] == true;
}

/// The signed-in user, again at every ID token change.
class WatchAccessChanges {
  const WatchAccessChanges(this._repository);
  final AdminAccessRepository _repository;

  Stream<AuthUser?> call() => _repository.watchToken();
}
