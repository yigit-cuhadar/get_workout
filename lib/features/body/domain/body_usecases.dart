import 'dart:async';

import 'package:forge_core/forge_core.dart';

import '../../profile/domain/profile_usecases.dart';
import '../../programs/domain/calendar_date.dart';
import '../../profile/domain/user_profile.dart';
import 'body_entry.dart';
import 'body_photo_sync.dart';
import 'body_photos.dart';
import 'body_repository.dart';
import 'body_stats.dart';
import 'body_validation.dart';

/// [entry.photos] are the photos kept as stored; [newPhotos] are pictures
/// just taken, by pose, as the camera's files, each replacing the stored
/// photo of its pose. [isNew] adds the entry, otherwise it replaces the
/// stored one.
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

/// The dates user [String] already had a measurement day on, again on
/// every change.
class WatchMeasuredDates {
  const WatchMeasuredDates(this._repository);
  final BodyRepository _repository;

  Stream<Set<CalendarDate>> call(String uid) =>
      _repository.watchEntries(uid).map(measuredDates);
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

/// Queues the backup of the user's photos the backup may be missing.
class ReconcileBodyPhotos {
  const ReconcileBodyPhotos(this._sync);
  final BodyPhotoSync _sync;

  Future<void> call(String uid, List<BodyEntry> entries) =>
      _sync.reconcile(uid, entries);
}

/// Removes a picture the camera took that is not kept: retaken, skipped,
/// or the flow was left.
class DiscardCapture {
  const DiscardCapture(this._store);
  final BodyPhotoStore _store;

  Future<void> call(String file) => _store.deleteCapture(file);
}

/// Stops a user's photo backup and drops what was queued; for the account
/// feature, before the server deletes the account.
class StopBodyPhotoBackup {
  const StopBodyPhotoBackup(this._sync);
  final BodyPhotoSync _sync;

  Future<void> call(String uid) => _sync.stop(uid);
}

/// Lets a user's photo backup go on: their account was not deleted.
class ResumeBodyPhotoBackup {
  const ResumeBodyPhotoBackup(this._sync);
  final BodyPhotoSync _sync;

  Future<void> call(String uid) => _sync.resume(uid);
}

/// Stops a user's photo backup for good and removes their photos from this
/// device; for the account feature, once the account is deleted.
class ForgetBodyPhotos {
  const ForgetBodyPhotos(this._sync);
  final BodyPhotoSync _sync;

  Future<Result<void>> call(String uid) => _sync.forget(uid);
}

/// Keeps `profile.weightKg` at the weight of the user's most recent entry
/// that has one (the calculators and the target weight use it). With no
/// such entry the profile is left as it is.
class SyncProfileWeight {
  const SyncProfileWeight(
    this._repository,
    this._watchProfile,
    this._updateProfile,
  );
  final BodyRepository _repository;
  final WatchProfile _watchProfile;
  final UpdateProfile _updateProfile;

  Future<void> call(String uid) async {
    try {
      // Firestore's cache already holds the write just made.
      final kg = latestWeightKg(await _repository.watchEntries(uid).first);
      if (kg == null) return;
      final profile = await _watchProfile(uid).first;
      if (profile.weightKg == kg) return;
      final saved = await _updateProfile((
        uid: uid,
        profile: profile.copyWith(weightKg: kg),
        fields: {ProfileField.weight},
      ));
      if (saved.failureOrNull case final failure?) {
        Log.e('body', 'profile weight not updated: ${failure.message}');
      }
    } on Object catch (error, stack) {
      Log.e('body', 'profile weight not updated', error, stack);
    }
  }
}

/// Saves an entry with its new photos as one change. All photos are stored
/// first; a photo that cannot be, or an entry that cannot be written,
/// removes what this attempt stored, so nothing is half saved and a retry
/// starts clean. Only then are uploads queued and the camera's files
/// removed. Once the server confirms, the photos the new ones replaced are
/// removed, here and in the backup; if it refuses, the new ones are, so
/// the undone save leaves nothing behind. An invalid entry is refused with
/// a [ValidationFailure] before anything is written.
class SaveBodyEntry implements UseCase<void, BodySave> {
  SaveBodyEntry(
    this._repository,
    this._store,
    this._sync,
    this._syncProfileWeight, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final BodyRepository _repository;
  final BodyPhotoStore _store;
  final BodyPhotoSync _sync;
  final SyncProfileWeight _syncProfileWeight;
  final DateTime Function() _clock;

  @override
  Future<Result<void>> call(BodySave params) async {
    final BodySave(:uid, :newPhotos) = params;
    final given = params.entry;
    final now = _clock();
    final added = {
      for (final pose in newPhotos.keys)
        pose: photoPath(uid, given.id, pose, now.millisecondsSinceEpoch),
    };
    final entry = BodyEntry(
      id: given.id,
      date: given.date,
      weightKg: given.weightKg,
      measurements: given.measurements,
      photos: {...given.photos, ...added},
    );
    final issues = validateBodyEntry(entry, now: now);
    if (issues.isNotEmpty) {
      return Err(ValidationFailure(issues.map((i) => i.name).join(', ')));
    }
    final stored = <String>[];
    Future<Result<void>> undo(Failure failure) async {
      await _store.delete(stored);
      return Err(failure);
    }

    for (final MapEntry(key: pose, value: source) in newPhotos.entries) {
      final path = added[pose]!;
      if ((await _store.save(path, source)).failureOrNull case final failure?) {
        return undo(failure);
      }
      stored.add(path);
    }
    final written = params.isNew
        ? await _repository.addEntry(uid, entry)
        : await _repository.updateEntry(uid, entry);
    final Confirmation confirmation;
    switch (written) {
      case Err(:final failure):
        return undo(failure);
      case Ok(:final value):
        confirmation = value;
    }
    await _sync.upload(stored);
    for (final source in newPhotos.values) {
      await _store.deleteCapture(source);
    }
    final replaced = [for (final pose in newPhotos.keys) ?given.photos[pose]];
    unawaited(
      confirmation.then(
        (refused) => _remove(refused == null ? replaced : stored),
      ),
    );
    await _syncProfileWeight(uid);
    return const Ok(null);
  }

  Future<void> _remove(List<String> paths) async {
    if (paths.isEmpty) return;
    if ((await _store.delete(paths)).failureOrNull case final failure?) {
      Log.e('body', 'photos left on the device: ${failure.message}');
    }
    await _sync.delete(paths);
  }
}

/// Deletes the entry. Its photos, here and in the backup, are removed only
/// once the server confirms, so a refused delete, which brings the entry
/// back, still has them.
class DeleteBodyEntry implements UseCase<void, BodyDelete> {
  const DeleteBodyEntry(
    this._repository,
    this._store,
    this._sync,
    this._syncProfileWeight,
  );
  final BodyRepository _repository;
  final BodyPhotoStore _store;
  final BodyPhotoSync _sync;
  final SyncProfileWeight _syncProfileWeight;

  @override
  Future<Result<void>> call(BodyDelete params) async {
    final BodyDelete(:uid, :entry) = params;
    final started = await _repository.deleteEntry(uid, entry.id);
    final Confirmation confirmation;
    switch (started) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        confirmation = value;
    }
    final paths = entry.photos.values.toList();
    if (paths.isNotEmpty) {
      unawaited(
        confirmation.then((refused) async {
          if (refused != null) return;
          if ((await _store.delete(paths)).failureOrNull case final failure?) {
            Log.e('body', 'photos left on the device: ${failure.message}');
          }
          await _sync.delete(paths);
        }),
      );
    }
    await _syncProfileWeight(uid);
    return const Ok(null);
  }
}
