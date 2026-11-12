import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:forge_core/forge_core.dart';
import 'package:image/image.dart' as img;

import '../domain/body_entry.dart';
import '../domain/body_photos.dart';

/// Photos as files under [_directory] (the app's private support
/// directory), each at its storage path. Paths come from Firestore, so only
/// photo paths are accepted; nothing can point outside the directory. The
/// photos' folder is kept out of the device's own backups through
/// [_excludeFromBackup]: their only copies are here and in our backup.
class FileBodyPhotoStore implements BodyPhotoStore {
  const FileBodyPhotoStore(this._directory, {required this._excludeFromBackup});

  final Future<Directory> Function() _directory;
  final Future<void> Function(String path) _excludeFromBackup;

  static final _photoPath = RegExp(
    r'^users/[A-Za-z0-9_-]+/photos/[A-Za-z0-9_-]+/'
    r'(front|right|left|back)-[0-9]+\.jpg$',
  );
  static final _uid = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The longer side of a stored photo; with [_quality] a photo stays far
  /// below the backup's 5 MB.
  static const maxSide = 1600;
  static const _quality = 85;

  /// Shrunk to [maxSide], turned upright (cameras store some pictures
  /// sideways with an orientation tag) and stripped of its metadata
  /// (location, device), off the UI isolate.
  @override
  Future<Result<String>> save(String path, String sourceFile) =>
      guard(() async {
        final target = await _file(path);
        final jpeg = await Isolate.run(() => _shrink(sourceFile));
        return _write(target, jpeg);
      });

  @override
  Future<Result<String>> saveBytes(String path, List<int> jpeg) =>
      guard(() async => _write(await _file(path), jpeg));

  static Future<List<int>> _shrink(String sourceFile) async {
    final decoded = img.decodeImage(await File(sourceFile).readAsBytes());
    if (decoded == null) {
      throw ValidationFailure('not a picture: $sourceFile');
    }
    final upright = img.bakeOrientation(decoded);
    final landscape = upright.width >= upright.height;
    final resized = math.max(upright.width, upright.height) <= maxSide
        ? upright
        : img.copyResize(
            upright,
            width: landscape ? maxSide : null,
            height: landscape ? null : maxSide,
            interpolation: img.Interpolation.average,
          );
    resized.exif = img.ExifData();
    return img.encodeJpg(resized, quality: _quality);
  }

  /// Written beside the photo, then renamed over it, so a photo is never
  /// half written.
  Future<String> _write(File target, List<int> jpeg) async {
    await target.parent.create(recursive: true);
    await _excludeFromBackup('${(await _directory()).path}/users');
    final partial = File('${target.path}.partial');
    await partial.writeAsBytes(jpeg, flush: true);
    await partial.rename(target.path);
    return target.path;
  }

  @override
  Future<Map<String, String>> find(Iterable<String> paths) async {
    final found = <String, String>{};
    try {
      for (final path in paths.toSet()) {
        if (!_photoPath.hasMatch(path)) continue;
        final file = await _file(path);
        if (await file.exists()) found[path] = file.path;
      }
    } on Object catch (error, stack) {
      Log.e('body', 'could not look for photos', error, stack);
    }
    return found;
  }

  /// Also removes the entry's folder once it is empty.
  @override
  Future<Result<void>> delete(Iterable<String> paths) => guard(() async {
    for (final path in paths) {
      final file = await _file(path);
      if (await file.exists()) await file.delete();
      final folder = file.parent;
      if (await folder.exists() && await folder.list().isEmpty) {
        await folder.delete();
      }
    }
  });

  @override
  Future<Result<void>> deleteUser(String uid) => guard(() async {
    if (!_uid.hasMatch(uid)) throw ValidationFailure('not a uid: $uid');
    final folder = Directory(
      '${(await _directory()).path}/${photoFolder(uid)}',
    );
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  @override
  Future<void> deleteCapture(String file) async {
    try {
      final capture = File(file);
      if (await capture.exists()) await capture.delete();
    } on Object catch (error, stack) {
      Log.e('body', 'camera file left behind', error, stack);
    }
  }

  Future<File> _file(String path) async {
    if (!_photoPath.hasMatch(path)) {
      throw ValidationFailure('not a photo path: $path');
    }
    return File('${(await _directory()).path}/$path');
  }
}
