import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../domain/body_photos.dart';

/// The backup state of every photo as JSON
/// (`{"version": 1, "photos": {"<path>": "upload" | "delete" | "uploaded"}}`)
/// in [_directory]. Writes run one at a time, each replacing the file whole
/// (temporary file, then rename) with the newest states, so a crash leaves
/// the previous version. A file that cannot be read is renamed
/// `<name>.unreadable-<time>`, never overwritten, and reported.
class FileBackupQueue implements BackupQueue {
  FileBackupQueue(this._directory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  Future<void> _tail = Future.value();

  /// The newest states waiting to be written, if any.
  String? _next;

  static const version = 1;
  static const fileName = 'body_photo_backup.json';

  @override
  Future<Result<Map<String, BackupState>>> load() => guard(() async {
    await _tail;
    final file = await _file();
    if (FileSystemEntity.typeSync(file.path) == FileSystemEntityType.notFound) {
      return {};
    }
    try {
      final json = jsonDecode(await file.readAsString());
      if (json case {
        'version': version,
        'photos': final Map<Object?, Object?> photos,
      }) {
        final states = BackupState.values.asNameMap();
        return {
          for (final MapEntry(:key, :value) in photos.entries)
            if ((key, states[value]) case (final String path, final state?))
              path: state,
        };
      }
      throw const FormatException('unknown backup queue');
    } on Object catch (error, stack) {
      Log.e('body', 'backup queue unreadable', error, stack);
      final aside =
          '${file.path}.unreadable-${_clock().millisecondsSinceEpoch}';
      await file.rename(aside);
      throw UnknownFailure('backup queue unreadable; moved to $aside', error);
    }
  });

  @override
  Future<Result<void>> save(Map<String, BackupState> states) {
    _next = jsonEncode({
      'version': version,
      'photos': {
        for (final MapEntry(:key, :value) in states.entries) key: value.name,
      },
    });
    final run = _tail.then((_) => _flush());
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  /// Writes what is waiting, unless an earlier flush already did.
  Future<void> _flush() async {
    final content = _next;
    _next = null;
    if (content == null) return;
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.partial');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');
}
