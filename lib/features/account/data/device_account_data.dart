import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../../body/domain/body_usecases.dart';
import '../../workout/domain/workout_repository.dart';
import '../domain/account_repository.dart';

/// A user's data on this device: their kept workouts (in progress and
/// waiting to sync), their progress photos and photo backup queue, every
/// scheduled notification (rest and reminders all belong to whoever is
/// signed in), and Firestore's offline copy.
///
/// The offline copy can only be cleared before Firestore is first used, so
/// [clear] leaves a marker file in [_directory] and
/// [clearOfflineCopyIfMarked] does it at the next start.
class DeviceAccountData implements LocalAccountData {
  const DeviceAccountData(
    this._workouts,
    this._notifications,
    this._directory, {
    required this._stopPhotoBackup,
    required this._resumePhotoBackup,
    required this._forgetPhotos,
  });

  final StopBodyPhotoBackup _stopPhotoBackup;
  final ResumeBodyPhotoBackup _resumePhotoBackup;
  final ForgetBodyPhotos _forgetPhotos;
  final LocalWorkoutStore _workouts;
  final Future<Notifications> _notifications;
  final Future<Directory> Function() _directory;

  static const _marker = 'clear_offline_copy';

  @override
  Future<void> holdWrites(String uid) => _stopPhotoBackup(uid);

  @override
  Future<void> releaseWrites(String uid) => _resumePhotoBackup(uid);

  @override
  Future<Result<void>> clear(String uid) async {
    final results = await Future.wait([
      _forgetPhotos(uid),
      guard(() async {
        final marker = File('${(await _directory()).path}/$_marker');
        await marker.parent.create(recursive: true);
        await marker.writeAsString('', flush: true);
      }),
      _workouts.remove(uid),
      _notifications.then((notifications) => notifications.cancelAll()),
    ]);
    return results.firstWhere(
      (result) => !result.isOk,
      orElse: () => const Ok(null),
    );
  }

  /// Call at start, before anything uses [firestore]. Best effort: a
  /// failure is logged and the marker kept, so the next start tries again.
  static Future<void> clearOfflineCopyIfMarked(
    Future<Directory> Function() directory,
    FirebaseFirestore firestore,
  ) async {
    final result = await guard(() async {
      final marker = File('${(await directory()).path}/$_marker');
      if (!marker.existsSync()) return;
      await firestore.clearPersistence();
      await marker.delete();
    });
    if (result.failureOrNull case final failure?) {
      Log.e('account', 'offline copy not cleared: ${failure.message}');
    }
  }
}
