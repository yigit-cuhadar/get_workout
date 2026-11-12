import 'dart:async';

import 'package:forge_core/forge_core.dart';

import 'body_photos.dart';

/// Keeps the backup in step with the photos on the device, without ever
/// making the user wait for the network. Uploads and deletions are queued
/// on the device, then done in the background for whoever is signed in
/// (the rules let only the owner write their photos). Work that fails, e.g.
/// offline, stays queued and is tried again on the next [run]: at start,
/// on every sign-in, when the app resumes and when more work is queued.
class BodyPhotoSync {
  BodyPhotoSync(this._queue, this._store, this._backup);

  final BackupQueue _queue;
  final BodyPhotoStore _store;
  final BodyPhotoBackup _backup;

  late final Future<Map<String, BackupTask>> _tasks = _queue.load().then(
    (loaded) => {...?loaded.valueOrNull},
  );

  /// Bumped on every change of a path's task, so a task replaced while it
  /// ran is not taken off the queue as done.
  final _versions = <String, int>{};
  final _restoring = <String, Future<String?>>{};
  StreamSubscription<String?>? _users;
  String? _uid;
  bool _running = false;
  bool _again = false;

  /// Follows [userIds], running the queue for each user signed in.
  void start(Stream<String?> userIds) {
    unawaited(_users?.cancel());
    _users = userIds.distinct().listen((uid) {
      _uid = uid;
      unawaited(run());
    });
  }

  /// Queues the backup of the photo at [path], replacing what was queued.
  Future<void> upload(String path) => _queueTask([path], BackupTask.upload);

  /// Queues the removal of the copies of [paths].
  Future<void> delete(Iterable<String> paths) =>
      _queueTask(paths, BackupTask.delete);

  Future<void> _queueTask(Iterable<String> paths, BackupTask task) async {
    final tasks = await _tasks;
    for (final path in paths) {
      tasks[path] = task;
      _versions[path] = (_versions[path] ?? 0) + 1;
    }
    await _persist(tasks);
    unawaited(run());
  }

  /// Does the queued work of the signed-in user, oldest first, until done
  /// or something fails.
  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final uid = _uid;
        if (uid == null) return;
        final tasks = await _tasks;
        for (final MapEntry(key: path, value: task) in tasks.entries.toList()) {
          if (!path.startsWith('users/$uid/')) continue;
          final version = _versions[path];
          if (!await _do(path, task)) {
            Log.e('body', 'photo backup paused; retried later');
            return;
          }
          if (_versions[path] == version) {
            tasks.remove(path);
            await _persist(tasks);
          }
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<bool> _do(String path, BackupTask task) async {
    switch (task) {
      case BackupTask.upload:
        final file = (await _store.find([path]))[path];
        // Gone from the device before it was backed up: nothing to copy.
        if (file == null) return true;
        return (await _backup.upload(path, file)).isOk;
      case BackupTask.delete:
        return (await _backup.delete(path)).isOk;
    }
  }

  /// The file of the photo at [path], fetched from the backup when it is
  /// not on this device (e.g. a new phone); null when there is no copy or
  /// it cannot be fetched now. Only the signed-in user's photos.
  Future<String?> restore(String path) =>
      _restoring[path] ??= _restore(path).whenComplete(() {
        // A block: returning the removed future would wait on itself.
        _restoring.remove(path);
      });

  Future<String?> _restore(String path) async {
    final present = (await _store.find([path]))[path];
    if (present != null) return present;
    final uid = _uid;
    if (uid == null || !path.startsWith('users/$uid/')) return null;
    // A copy queued for removal is not brought back.
    if ((await _tasks)[path] == BackupTask.delete) return null;
    final downloaded = await _backup.download(path);
    final jpeg = downloaded.valueOrNull;
    if (jpeg == null) return null;
    return (await _store.saveBytes(path, jpeg)).valueOrNull;
  }

  Future<void> _persist(Map<String, BackupTask> tasks) async {
    if ((await _queue.save(tasks)).failureOrNull case final failure?) {
      Log.e('body', 'backup queue not saved: ${failure.message}');
    }
  }

  Future<void> cancel() async => _users?.cancel();
}
