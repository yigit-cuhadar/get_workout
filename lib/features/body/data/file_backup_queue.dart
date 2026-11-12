import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../domain/body_photos.dart';

/// The queue as JSON (`{"<path>": "upload" | "delete"}`) in [_directory],
/// replaced whole on every save, so it is never half written. A file that
/// cannot be read counts as empty: the photos stay on the device, only
/// their backup may then lag.
class FileBackupQueue implements BackupQueue {
  const FileBackupQueue(this._directory);

  final Future<Directory> Function() _directory;

  @override
  Future<Result<Map<String, BackupTask>>> load() => guard(() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      return {
        if (json is Map)
          for (final MapEntry(:key, :value) in json.entries)
            if ((key, BackupTask.values.asNameMap()[value]) case (
              final String path,
              final task?,
            ))
              path: task,
      };
    } on FormatException catch (error, stack) {
      Log.e('body', 'unreadable backup queue', error, stack);
      return {};
    }
  });

  @override
  Future<Result<void>> save(Map<String, BackupTask> tasks) => guard(() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.partial');
    await partial.writeAsString(
      jsonEncode({
        for (final MapEntry(:key, :value) in tasks.entries) key: value.name,
      }),
    );
    await partial.rename(file.path);
  });

  Future<File> _file() async =>
      File('${(await _directory()).path}/body_photo_backup.json');
}
