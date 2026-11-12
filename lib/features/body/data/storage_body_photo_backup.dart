import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/body_photos.dart';

/// The photos in Cloud Storage, at their paths. Only their owner may read
/// or write them (`storage.rules`).
class StorageBodyPhotoBackup implements BodyPhotoBackup {
  const StorageBodyPhotoBackup(this._storage);

  final FirebaseStorage _storage;

  /// What the rules accept.
  static const maxBytes = 5 * 1024 * 1024;

  @override
  Future<Result<void>> upload(String path, String localFile) => guard(
    () => _storage
        .ref(path)
        .putFile(File(localFile), SettableMetadata(contentType: 'image/jpeg')),
    mapper: _map,
  );

  @override
  Future<Result<List<int>>> download(String path) => guard(() async {
    final bytes = await _storage.ref(path).getData(maxBytes);
    if (bytes == null) throw const NotFoundFailure();
    return bytes;
  }, mapper: _map);

  @override
  Future<Result<void>> delete(String path) => guard(() async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }, mapper: _map);

  static Failure? _map(Object error) =>
      error is FirebaseException && error.code == 'object-not-found'
      ? NotFoundFailure(error.message ?? error.code, error)
      : mapFirebaseError(error);
}
