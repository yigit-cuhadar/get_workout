import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

abstract interface class AdminAccessRepository {
  /// Emits the signed-in user (null when signed out) whenever the ID token
  /// changes: at sign-in and sign-out, and at every token refresh, which is
  /// when a granted or revoked claim arrives.
  Stream<AuthUser?> watchToken();

  /// The custom claims in the signed-in user's ID token; empty when signed
  /// out. With [refresh], a new token is fetched first: a claim granted after
  /// the current token was issued only arrives that way.
  Future<Result<Map<String, Object?>>> claims({required bool refresh});
}
