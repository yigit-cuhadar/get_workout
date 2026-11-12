import 'dart:async';

import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:mocktail/mocktail.dart';

/// The queue in memory; [saved] is what was last written.
class FakeBackupQueue implements BackupQueue {
  FakeBackupQueue([Map<String, BackupState> stored = const {}])
    : saved = {...stored};

  Map<String, BackupState> saved;
  Failure? loadFailure;

  @override
  Future<Result<Map<String, BackupState>>> load() async {
    final failure = loadFailure;
    return failure == null ? Ok({...saved}) : Err(failure);
  }

  @override
  Future<Result<void>> save(Map<String, BackupState> states) async {
    saved = {...states};
    return const Ok(null);
  }
}

/// Photos on the "device", by path; a stored photo's file is `local/<path>`.
class FakePhotoStore implements BodyPhotoStore {
  final files = <String, String>{};
  final bytes = <String, List<int>>{};
  final discarded = <String>[];
  final forgotten = <String>[];

  /// When each photo was written; unset ones are old.
  final written = <String, DateTime>{};

  /// Paths whose save fails.
  final failing = <String>{};

  @override
  Future<Result<String>> save(String path, String sourceFile) async {
    if (failing.any(path.contains)) {
      return const Err(UnknownFailure('disk full'));
    }
    return Ok(files[path] = 'local/$path');
  }

  @override
  Future<Result<String>> saveBytes(String path, List<int> jpeg) async {
    bytes[path] = jpeg;
    return Ok(files[path] = 'local/$path');
  }

  /// When set, the next look reports what it saw only once this
  /// completes, as a slow disk would.
  Completer<void>? findGate;

  @override
  Future<Map<String, String>> find(Iterable<String> paths) async {
    final found = {for (final path in paths) path: ?files[path]};
    final gate = findGate;
    findGate = null;
    await gate?.future;
    return found;
  }

  @override
  Future<Result<void>> delete(Iterable<String> paths) async {
    paths.forEach(files.remove);
    return const Ok(null);
  }

  @override
  Future<Map<String, DateTime>> stored(String uid) async => {
    for (final path in files.keys)
      if (isPhotoOf(path, uid)) path: written[path] ?? DateTime(2000),
  };

  @override
  Future<Result<void>> deleteUser(String uid) async {
    forgotten.add(uid);
    files.removeWhere((path, _) => isPhotoOf(path, uid));
    return const Ok(null);
  }

  @override
  Future<void> deleteCapture(String file) async => discarded.add(file);
}

/// The copies "in the cloud", by path; nothing works while not [online].
/// While [gate] is set, uploads wait for it.
class FakeBackup implements BodyPhotoBackup {
  final remote = <String, String>{};
  final calls = <String>[];
  bool online = true;
  Completer<void>? gate;

  /// Uploads refused as by the rules, e.g. after their owner signed out.
  final refused = <String>{};

  @override
  Future<Result<void>> upload(String path, String localFile) async {
    calls.add('upload $path');
    await gate?.future;
    if (!online) return const Err(NetworkFailure());
    if (refused.contains(path)) return const Err(PermissionFailure());
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

/// Entries in memory. Writes confirm at once unless [holdConfirmations];
/// then [confirm] settles them in order.
class FakeBodyRepository implements BodyRepository {
  final entries = <String, BodyEntry>{};
  final calls = <String>[];
  Failure? startFailure;
  bool holdConfirmations = false;
  final _pending = <Completer<Failure?>>[];
  var _ids = 0;

  @override
  Stream<List<BodyEntry>> watchEntries(String uid) => Stream.value(
    entries.values.toList()..sort((a, b) => b.date.compareTo(a.date)),
  );

  /// Completes when the server has answered; never, until a test says so.
  final server = Completer<void>();

  @override
  Future<List<BodyEntry>> confirmedEntries(String uid) async {
    await server.future;
    return entries.values.toList();
  }

  @override
  String newEntryId(String uid) => 'id${++_ids}';

  @override
  Future<Result<Confirmation>> addEntry(String uid, BodyEntry entry) =>
      _write('add ${entry.id}', () => entries[entry.id] = entry);

  @override
  Future<Result<Confirmation>> updateEntry(String uid, BodyEntry entry) =>
      _write('update ${entry.id}', () => entries[entry.id] = entry);

  @override
  Future<Result<Confirmation>> deleteEntry(String uid, String id) =>
      _write('delete $id', () => entries.remove(id));

  Future<Result<Confirmation>> _write(
    String call,
    void Function() apply,
  ) async {
    calls.add(call);
    final failure = startFailure;
    if (failure != null) return Err(failure);
    apply();
    if (!holdConfirmations) return Ok(Future.value());
    final completer = Completer<Failure?>();
    _pending.add(completer);
    return Ok(completer.future);
  }

  /// Settles the oldest unconfirmed write: taken, or refused with [refused].
  Future<void> confirm([Failure? refused]) async {
    _pending.removeAt(0).complete(refused);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Stream<Failure> get rejectedWrites => const Stream.empty();
}

class FakeProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile();

  @override
  Stream<UserProfile> watchProfile(String uid) => Stream.value(profile);

  @override
  Future<Result<void>> saveFields(
    String uid,
    UserProfile profile,
    Set<ProfileField> fields,
  ) async {
    this.profile = profile;
    return const Ok(null);
  }

  @override
  Future<Result<void>> completeOnboarding(String uid, UserProfile answers) =>
      throw UnimplementedError();
}

class _MockLibrary extends Mock implements UserLibraryRepository {}

SyncProfileWeight syncProfileWeight(
  BodyRepository repository,
  ProfileRepository profiles,
) => SyncProfileWeight(
  repository,
  WatchProfile(profiles),
  UpdateProfile(profiles, SaveOwnedEquipment(_MockLibrary())),
);

/// The photo pipeline of the body feature over fakes.
class BodyPhotoWorld {
  final repository = FakeBodyRepository();
  final store = FakePhotoStore();
  final queue = FakeBackupQueue();
  final backup = FakeBackup();
  final profiles = FakeProfileRepository();
  late final sync = BodyPhotoSync(queue, store, backup, repository);

  SaveBodyEntry save(DateTime Function() clock) => SaveBodyEntry(
    repository,
    store,
    sync,
    syncProfileWeight(repository, profiles),
    clock: clock,
  );

  DeleteBodyEntry delete() => DeleteBodyEntry(
    repository,
    store,
    sync,
    syncProfileWeight(repository, profiles),
  );
}
