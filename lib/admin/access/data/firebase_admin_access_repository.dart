import 'package:firebase_auth/firebase_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/admin_access_repository.dart';

class FirebaseAdminAccessRepository implements AdminAccessRepository {
  const FirebaseAdminAccessRepository(this._auth);
  final FirebaseAuth _auth;

  @override
  Future<Result<Map<String, Object?>>> claims({required bool refresh}) =>
      guard(() async {
        final token = await _auth.currentUser?.getIdTokenResult(refresh);
        return Map<String, Object?>.of(token?.claims ?? const {});
      }, mapper: mapFirebaseError);
}
