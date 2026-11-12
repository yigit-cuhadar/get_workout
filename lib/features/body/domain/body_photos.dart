import 'package:forge_core/forge_core.dart';

/// Progress photos in the app's private storage, never the gallery and
/// never the device's own backups, each at its storage path (see
/// `photoPath`).
abstract interface class BodyPhotoStore {
  /// Stores the picture in [sourceFile] at [path] as a JPEG small enough
  /// to back up and without metadata, and returns the stored file.
  Future<Result<String>> save(String path, String sourceFile);

  /// Stores [jpeg], a photo fetched from the backup, at [path].
  Future<Result<String>> saveBytes(String path, List<int> jpeg);

  /// The files of those of [paths] that are on this device, by path.
  Future<Map<String, String>> find(Iterable<String> paths);

  /// Removes the photos at [paths]; missing ones are fine.
  Future<Result<void>> delete(Iterable<String> paths);

  /// [uid]'s photos on this device, by path, with when each was written.
  Future<Map<String, DateTime>> stored(String uid);

  /// Removes every photo of [uid] from this device.
  Future<Result<void>> deleteUser(String uid);

  /// Removes a picture the camera left in a temporary file; a missing one
  /// is fine.
  Future<void> deleteCapture(String file);
}

/// A copy of the photos off the device, at the same paths.
abstract interface class BodyPhotoBackup {
  Future<Result<void>> upload(String path, String localFile);

  /// A [NotFoundFailure] when there is no copy.
  Future<Result<List<int>>> download(String path);

  /// Fine when there is no copy.
  Future<Result<void>> delete(String path);
}

/// Where a photo stands with the backup.
enum BackupState {
  /// To be copied to the backup.
  upload,

  /// Its copy is to be removed.
  delete,

  /// The backup has it.
  uploaded,
}

/// The backup state of each photo, kept on the device so pending work
/// survives the app being closed.
abstract interface class BackupQueue {
  /// Empty when nothing was stored. A store that cannot be read is put
  /// aside, never overwritten, and reported as a failure.
  Future<Result<Map<String, BackupState>>> load();

  Future<Result<void>> save(Map<String, BackupState> states);
}
