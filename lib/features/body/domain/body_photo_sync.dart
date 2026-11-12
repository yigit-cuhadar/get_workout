import 'dart:async';

import 'package:forge_core/forge_core.dart';

import 'body_entry.dart';
import 'body_photos.dart';
import 'body_repository.dart';

/// Keeps the backup in step with the photos on the device, without ever
/// making the user wait for the network. Every photo's backup state is kept
/// on the device; uploads and deletions are done in the background for
/// whoever is signed in (the rules let only the owner write their photos).
/// Work that fails, e.g. offline, stays queued and is tried again on the
/// next [run]: at start, on every sign-in, when the app resumes and when
/// more work is queued.
/// A signed-in user as the backup needs to know them.
typedef BodyPhotoUser = ({String id, bool guest});

class BodyPhotoSync {
  BodyPhotoSync(
    this._queue,
    this._store,
    this._backup,
    this._repository, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BackupQueue _queue;
  final BodyPhotoStore _store;
  final BodyPhotoBackup _backup;
  final BodyRepository _repository;
  final DateTime Function() _clock;

  /// A photo written more recently is never taken for an orphan: its save
  /// may still be under way.
  static const orphanAge = Duration(minutes: 10);

  /// A queue that cannot be read starts empty; [reconcile] then queues
  /// again what the backup may be missing.
  late final Future<Map<String, BackupState>> _states = _queue.load().then(
    (loaded) => switch (loaded) {
      Ok(:final value) => {...value},
      Err(:final failure) => () {
        Log.e('body', 'backup queue lost: ${failure.message}');
        return <String, BackupState>{};
      }(),
    },
  );

  /// Bumped on every change of a path's state, so a task replaced while it
  /// ran does not record its outcome.
  final _versions = <String, int>{};
  final _restoring = <String, Future<String?>>{};
  StreamSubscription<BodyPhotoUser?>? _users;
  String? _uid;
  bool _running = false;

  /// Users whose account is being deleted: nothing of theirs is queued or
  /// sent until [resume].
  final _stopped = <String>{};

  /// The task in progress, if any.
  Future<bool>? _current;

  /// Follows [users], running the queue for each user signed in and
  /// clearing their orphaned photos once. A guest who is left (signed out,
  /// or replaced by signing in to an existing account) can never come
  /// back, so their photos on this device are forgotten.
  void start(Stream<BodyPhotoUser?> users) {
    unawaited(_users?.cancel());
    BodyPhotoUser? previous;
    _users = users.distinct().listen((user) {
      final left = previous;
      previous = user;
      _uid = user?.id;
      if (left != null && left.guest && left.id != user?.id) {
        unawaited(forget(left.id));
      }
      if (user != null) unawaited(_removeOrphans(user.id));
      unawaited(run());
    });
  }

  /// Queues the backup of the photos at [paths].
  Future<void> upload(Iterable<String> paths) =>
      _set(paths, BackupState.upload);

  /// Queues the removal of the copies of [paths].
  Future<void> delete(Iterable<String> paths) =>
      _set(paths, BackupState.delete);

  Future<void> _set(Iterable<String> paths, BackupState state) async {
    final allowed = [
      for (final path in paths)
        if (!_isStopped(path)) path,
    ];
    if (allowed.isEmpty) return;
    final states = await _states;
    for (final path in allowed) {
      states[path] = state;
      _bump(path);
    }
    await _persist(states);
    unawaited(run());
  }

  void _bump(String path) => _versions[path] = (_versions[path] ?? 0) + 1;

  /// Queues the backup of [uid]'s photos that [entries] name, are on this
  /// device and are not known to the backup: after the queue was lost, or
  /// from before the backup existed.
  Future<void> reconcile(String uid, List<BodyEntry> entries) async {
    final states = await _states;
    final unknown = [
      for (final entry in entries)
        for (final path in entry.photos.values)
          if (isPhotoOf(path, uid) && !states.containsKey(path)) path,
    ];
    if (unknown.isEmpty) return;
    final present = await _store.find(unknown);
    await upload([
      for (final path in present.keys)
        if (!states.containsKey(path)) path,
    ]);
  }

  /// Does the queued work of whoever is signed in, one photo at a time,
  /// until done or something fails. The user is checked before each task;
  /// when they change while a task fails, the new user's work goes on.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final uid = _uid;
        if (uid == null || _stopped.contains(uid)) return;
        final states = await _states;
        final next = states.entries
            .where(
              (entry) =>
                  entry.value != BackupState.uploaded &&
                  isPhotoOf(entry.key, uid),
            )
            .firstOrNull;
        if (next == null) return;
        final MapEntry(key: path, value: state) = next;
        final version = _versions[path];
        final task = _current = _do(path, state);
        final done = await task;
        _current = null;
        if (!done) {
          if (_uid != uid) continue;
          Log.e('body', 'photo backup paused; retried later');
          return;
        }
        if (_versions[path] != version) continue;
        if (state == BackupState.delete) {
          states.remove(path);
        } else {
          states[path] = BackupState.uploaded;
        }
        await _persist(states);
      }
    } finally {
      _running = false;
    }
  }

  Future<bool> _do(String path, BackupState state) async {
    switch (state) {
      case BackupState.upload:
        final file = (await _store.find([path]))[path];
        // Gone from the device before it was backed up: nothing to copy,
        // and the entry naming it was undone or deleted.
        if (file == null) return true;
        return (await _backup.upload(path, file)).isOk;
      case BackupState.delete:
        return (await _backup.delete(path)).isOk;
      case BackupState.uploaded:
        return true;
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
    if (uid == null || !isPhotoOf(path, uid) || _stopped.contains(uid)) {
      return null;
    }
    final states = await _states;
    // A copy queued for removal is not brought back.
    if (states[path] == BackupState.delete) return null;
    final jpeg = (await _backup.download(path)).valueOrNull;
    if (jpeg == null || _uid != uid) return null;
    final file = (await _store.saveBytes(path, jpeg)).valueOrNull;
    if (file != null && !states.containsKey(path)) {
      states[path] = BackupState.uploaded;
      _bump(path);
      await _persist(states);
    }
    return file;
  }

  /// Stops all backup work for [uid] and drops what was queued, then waits
  /// for the task in progress: before their account is deleted, so nothing
  /// reaches the server after it deleted their files.
  Future<void> stop(String uid) async {
    _stopped.add(uid);
    final states = await _states;
    final theirs = [
      for (final path in states.keys)
        if (isPhotoOf(path, uid)) path,
    ];
    theirs.forEach(states.remove);
    theirs.forEach(_bump);
    await _persist(states);
    await _current;
  }

  /// Lets [uid]'s backup go on after [stop]: their account was not
  /// deleted. What was dropped is queued again by the next [reconcile].
  Future<void> resume(String uid) async {
    if (_stopped.remove(uid)) unawaited(run());
  }

  /// [stop]s [uid]'s backup for good and removes their photos from this
  /// device: after their account is deleted, or when a guest is left.
  /// Their copies in the backup are left to the account deletion.
  Future<Result<void>> forget(String uid) async {
    await stop(uid);
    return _store.deleteUser(uid);
  }

  bool _isStopped(String path) => _stopped.any((uid) => isPhotoOf(path, uid));

  /// Removes [uid]'s photos on this device that no entry names and the
  /// queue does not know, once the server has answered: those of a save
  /// that never reached it (stored, then the app was killed before the
  /// entry was written, or the write was refused while it was closed).
  /// Photos written in the last [orphanAge] are kept.
  Future<void> _removeOrphans(String uid) async {
    final List<BodyEntry> entries;
    try {
      entries = await _repository.confirmedEntries(uid);
    } on Object catch (error, stack) {
      Log.e('body', 'orphaned photos left: no confirmed entries', error, stack);
      return;
    }
    if (_uid != uid || _stopped.contains(uid)) return;
    final named = {for (final entry in entries) ...entry.photos.values};
    final states = await _states;
    final recent = _clock().subtract(orphanAge);
    final orphans = [
      for (final MapEntry(key: path, value: written) in (await _store.stored(
        uid,
      )).entries)
        if (!named.contains(path) &&
            !states.containsKey(path) &&
            written.isBefore(recent))
          path,
    ];
    if (orphans.isEmpty) return;
    Log.d('body', 'removing ${orphans.length} orphaned photos');
    if ((await _store.delete(orphans)).failureOrNull case final failure?) {
      Log.e('body', 'orphaned photos left: ${failure.message}');
    }
  }

  Future<void> _persist(Map<String, BackupState> states) async {
    if ((await _queue.save(states)).failureOrNull case final failure?) {
      Log.e('body', 'backup queue not saved: ${failure.message}');
    }
  }

  Future<void> cancel() async => _users?.cancel();
}
