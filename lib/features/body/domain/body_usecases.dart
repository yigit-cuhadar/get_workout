import 'package:forge_core/forge_core.dart';

import 'body_entry.dart';
import 'body_photo_sync.dart';
import 'body_photos.dart';
import 'body_repository.dart';
import 'body_validation.dart';

/// [entry.photos] are the photos kept as stored; [newPhotos] are pictures
/// just taken, by pose, as files to file under the entry. [isNew] adds the
/// entry, otherwise it replaces the stored one.
typedef BodySave = ({
  String uid,
  BodyEntry entry,
  Map<PhotoPose, String> newPhotos,
  bool isNew,
});
typedef BodyDelete = ({String uid, BodyEntry entry});

class WatchBodyEntries {
  const WatchBodyEntries(this._repository);
  final BodyRepository _repository;

  Stream<List<BodyEntry>> call(String uid) => _repository.watchEntries(uid);
}

class WatchRejectedBodyWrites {
  const WatchRejectedBodyWrites(this._repository);
  final BodyRepository _repository;

  Stream<Failure> call() => _repository.rejectedWrites;
}

class NewBodyEntryId {
  const NewBodyEntryId(this._repository);
  final BodyRepository _repository;

  String call(String uid) => _repository.newEntryId(uid);
}

/// The files of the photos at those paths that are on this device.
class FindBodyPhotos {
  const FindBodyPhotos(this._store);
  final BodyPhotoStore _store;

  Future<Map<String, String>> call(Iterable<String> paths) =>
      _store.find(paths);
}

/// The file of a photo, fetched from the backup when it is not on this
/// device; null when that is not possible now.
class RestoreBodyPhoto {
  const RestoreBodyPhoto(this._sync);
  final BodyPhotoSync _sync;

  Future<String?> call(String path) => _sync.restore(path);
}

/// Files the new photos, queues their backup, then stores the entry. An
/// invalid entry is refused with a [ValidationFailure] before anything is
/// written; a photo that cannot be filed fails the save before the entry
/// is stored, so an entry never names a photo that was not kept. The backup
/// runs in the background; nothing here waits for the network.
class SaveBodyEntry implements UseCase<void, BodySave> {
  SaveBodyEntry(
    this._repository,
    this._store,
    this._sync, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final BodyRepository _repository;
  final BodyPhotoStore _store;
  final BodyPhotoSync _sync;
  final DateTime Function() _clock;

  @override
  Future<Result<void>> call(BodySave params) async {
    final BodySave(:uid, :newPhotos) = params;
    final given = params.entry;
    final entry = BodyEntry(
      id: given.id,
      date: given.date,
      weightKg: given.weightKg,
      measurements: given.measurements,
      photos: {
        ...given.photos,
        for (final pose in newPhotos.keys) pose: photoPath(uid, given.id, pose),
      },
    );
    final issues = validateBodyEntry(entry, now: _clock());
    if (issues.isNotEmpty) {
      return Err(ValidationFailure(issues.map((i) => i.name).join(', ')));
    }
    for (final MapEntry(key: pose, value: source) in newPhotos.entries) {
      final path = entry.photos[pose]!;
      if ((await _store.save(path, source)).failureOrNull case final failure?) {
        return Err(failure);
      }
      await _sync.upload(path);
    }
    return params.isNew
        ? _repository.addEntry(uid, entry)
        : _repository.updateEntry(uid, entry);
  }
}

/// Deletes the entry, then its photos on the device, and queues the removal
/// of their backup. Photos are kept when the entry could not be deleted.
class DeleteBodyEntry implements UseCase<void, BodyDelete> {
  const DeleteBodyEntry(this._repository, this._store, this._sync);
  final BodyRepository _repository;
  final BodyPhotoStore _store;
  final BodyPhotoSync _sync;

  @override
  Future<Result<void>> call(BodyDelete params) async {
    final BodyDelete(:uid, :entry) = params;
    final deleted = await _repository.deleteEntry(uid, entry.id);
    if (!deleted.isOk) return deleted;
    final paths = entry.photos.values;
    if (paths.isEmpty) return deleted;
    if ((await _store.delete(paths)).failureOrNull case final failure?) {
      Log.e('body', 'photos left on the device: ${failure.message}');
    }
    await _sync.delete(paths);
    return deleted;
  }
}
