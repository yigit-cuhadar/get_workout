import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/user_library_repository.dart';
import '../domain/vocabulary.dart';

/// Owned equipment is `profile.equipment` and favourites are
/// `favoriteExerciseIds` of `users/{uid}`, a document shared with other
/// features, so writes always merge. `FirestoreCollection` only offers
/// whole-document writes, hence the direct Firestore access.
class FirestoreUserLibraryRepository implements UserLibraryRepository {
  const FirestoreUserLibraryRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const _favorites = 'favoriteExerciseIds';

  @override
  Stream<Set<Equipment>?> watchEquipment(String uid) => _watch(uid, (data) {
    final profile = data?['profile'];
    final raw = profile is Map ? profile['equipment'] : null;
    if (raw is! List) return null;
    // Unknown codes (a newer app version's) are skipped, not fatal.
    return {for (final code in raw) ?Equipment.values.byCode(code)}
      ..remove(Equipment.bodyweight);
  });

  @override
  Future<Result<void>> saveEquipment(String uid, Set<Equipment> equipment) =>
      guard(
        () => _user(uid).set({
          'profile': {
            'equipment': [
              for (final item in Equipment.values)
                if (equipment.contains(item)) item.code,
            ],
          },
        }, SetOptions(merge: true)),
        mapper: mapFirebaseError,
      );

  @override
  Stream<Set<String>> watchFavorites(String uid) => _watch(uid, (data) {
    final raw = data?[_favorites];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  });

  @override
  Future<Result<void>> setFavorite(
    String uid,
    String exerciseId, {
    required bool favorite,
  }) => guard(
    () => _user(uid).set({
      _favorites: favorite
          ? FieldValue.arrayUnion([exerciseId])
          : FieldValue.arrayRemove([exerciseId]),
    }, SetOptions(merge: true)),
    mapper: mapFirebaseError,
  );

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  Stream<T> _watch<T>(
    String uid,
    T Function(Map<String, dynamic>? data) read,
  ) =>
      _user(uid)
          .snapshots()
          .map((snapshot) => read(snapshot.data()))
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stack, sink) {
                final failure =
                    mapFirebaseError(error) ?? UnknownFailure('$error', error);
                Log.e('library', failure.message, error, stack);
                sink.addError(failure, stack);
              },
            ),
          );
}
