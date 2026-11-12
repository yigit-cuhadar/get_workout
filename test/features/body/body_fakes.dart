import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';

/// The queue in memory; [saved] is what was last written.
class FakeBackupQueue implements BackupQueue {
  FakeBackupQueue([Map<String, BackupTask> stored = const {}])
    : saved = {...stored};

  Map<String, BackupTask> saved;

  @override
  Future<Result<Map<String, BackupTask>>> load() async => Ok({...saved});

  @override
  Future<Result<void>> save(Map<String, BackupTask> tasks) async {
    saved = {...tasks};
    return const Ok(null);
  }
}

/// Photos on the "device", by path; a stored photo's file is `local/<path>`.
class FakePhotoStore implements BodyPhotoStore {
  final files = <String, String>{};
  final bytes = <String, List<int>>{};
  bool failSave = false;

  @override
  Future<Result<String>> save(String path, String sourceFile) async {
    if (failSave) return const Err(UnknownFailure('disk full'));
    return Ok(files[path] = 'local/$path');
  }

  @override
  Future<Result<String>> saveBytes(String path, List<int> jpeg) async {
    bytes[path] = jpeg;
    return Ok(files[path] = 'local/$path');
  }

  @override
  Future<Map<String, String>> find(Iterable<String> paths) async => {
    for (final path in paths) path: ?files[path],
  };

  @override
  Future<Result<void>> delete(Iterable<String> paths) async {
    paths.forEach(files.remove);
    return const Ok(null);
  }
}

/// The copies "in the cloud", by path; nothing works while not [online].
class FakeBackup implements BodyPhotoBackup {
  final remote = <String, String>{};
  final calls = <String>[];
  bool online = true;

  @override
  Future<Result<void>> upload(String path, String localFile) async {
    calls.add('upload $path');
    if (!online) return const Err(NetworkFailure());
    remote[path] = localFile;
    return const Ok(null);
  }

  @override
  Future<Result<List<int>>> download(String path) async {
    calls.add('download $path');
    if (!online) return const Err(NetworkFailure());
    return remote.containsKey(path)
        ? const Ok([1, 2, 3])
        : const Err(NotFoundFailure());
  }

  @override
  Future<Result<void>> delete(String path) async {
    calls.add('delete $path');
    if (!online) return const Err(NetworkFailure());
    remote.remove(path);
    return const Ok(null);
  }
}
