import 'package:forge_core/forge_core.dart';

abstract interface class AdminAccessRepository {
  /// The custom claims in the signed-in user's ID token; empty when signed
  /// out. With [refresh], a new token is fetched first: a claim granted after
  /// the current token was issued only arrives that way.
  Future<Result<Map<String, Object?>>> claims({required bool refresh});
}
