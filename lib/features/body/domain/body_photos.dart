import 'package:forge_core/forge_core.dart';

/// Progress photos in the app's private storage, never the gallery, each at
/// its storage path (see `photoPath`).
abstract interface class BodyPhotoStore {
  /// Stores the picture in [sourceFile] at [path] as a JPEG small enough
  /// to back up, replacing any photo there, and returns the stored file.
  Future<Result<String>> save(String path, String sourceFile);

  /// Stores [jpeg], a photo fetched from the backup, at [path].
  Future<Result<String>> saveBytes(String path, List<int> jpeg);

  /// The files of those of [paths] that are on this device, by path.
  Future<Map<String, String>> find(Iterable<String> paths);

  /// Removes the photos at [paths]; missing ones are fine.
  Future<Result<void>> delete(Iterable<String> paths);
}

/// A copy of the photos off the device, at the same paths.
abstract interface class BodyPhotoBackup {
  Future<Result<void>> upload(String path, String localFile);

  /// A [NotFoundFailure] when there is no copy.
  Future<Result<List<int>>> download(String path);

  /// Fine when there is no copy.
  Future<Result<void>> delete(String path);
}

/// What the backup still has to do for a photo.
enum BackupTask { upload, delete }

/// The backup work not done yet, by photo path, kept on the device so it
/// survives the app being closed.
abstract interface class BackupQueue {
  Future<Result<Map<String, BackupTask>>> load();
  Future<Result<void>> save(Map<String, BackupTask> tasks);
}
