import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../settings/domain/user_settings.dart';
import 'data/backup_exclusion.dart';
import 'data/file_backup_queue.dart';
import 'data/file_body_photo_store.dart';
import 'data/firestore_body_repository.dart';
import 'data/storage_body_photo_backup.dart';
import 'domain/body_entry.dart';
import 'domain/body_photo_sync.dart';
import 'domain/body_photos.dart';
import 'domain/body_repository.dart';
import 'domain/body_usecases.dart';
import 'presentation/body_list_cubit.dart';
import 'presentation/measurement_day_cubit.dart';
import 'presentation/weight_form_cubit.dart';

/// Registers the weight log and measurement days. Needs `AuthModule` for
/// the current user, `ProgramsModule` for `WatchPremium` and
/// `ProfileModule`, whose use cases keep the profile weight.
class BodyModule implements FeatureModule {
  const BodyModule();

  static const _retryTime = Duration(minutes: 1);

  /// Starts backing up photos for whoever signs in; call once the app is
  /// up, and [resumed] whenever it returns to the foreground.
  static void startPhotoBackup(GetIt sl) =>
      sl<BodyPhotoSync>().start(sl<WatchAuthUser>()().map((user) => user?.id));

  static void resumed(GetIt sl) => unawaited(sl<BodyPhotoSync>().run());

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<BodyRepository>(
        () => FirestoreBodyRepository(FirebaseFirestore.instance),
      )
      ..registerLazySingleton<BodyPhotoStore>(
        () => FileBodyPhotoStore(
          getApplicationSupportDirectory,
          excludeFromBackup: backupExclusion(defaultTargetPlatform),
        ),
      )
      ..registerLazySingleton<BodyPhotoBackup>(
        () => StorageBodyPhotoBackup(
          // Offline, give up soon; the sync tries again later anyway.
          FirebaseStorage.instance
            ..setMaxUploadRetryTime(_retryTime)
            ..setMaxOperationRetryTime(_retryTime),
        ),
      )
      ..registerLazySingleton<BackupQueue>(
        () => FileBackupQueue(getApplicationSupportDirectory),
      )
      ..registerLazySingleton(() => BodyPhotoSync(sl(), sl(), sl()))
      ..registerFactory(() => WatchBodyEntries(sl()))
      ..registerFactory(() => WatchRejectedBodyWrites(sl()))
      ..registerFactory(() => NewBodyEntryId(sl()))
      ..registerFactory(() => FindBodyPhotos(sl()))
      ..registerFactory(() => RestoreBodyPhoto(sl()))
      ..registerFactory(() => ReconcileBodyPhotos(sl()))
      ..registerFactory(() => DiscardCapture(sl()))
      // For the account feature: before or after deleting an account, and
      // when a guest's data is discarded.
      ..registerFactory(() => ForgetBodyPhotos(sl()))
      ..registerFactory(() => SyncProfileWeight(sl(), sl(), sl()))
      ..registerFactory(() => SaveBodyEntry(sl(), sl(), sl(), sl()))
      ..registerFactory(() => DeleteBodyEntry(sl(), sl(), sl(), sl()))
      // One list for the whole app: every body page shares it.
      ..registerLazySingleton(
        () => BodyListCubit(
          watchAuthUser: sl(),
          watchEntries: sl(),
          watchRejectedWrites: sl(),
          watchPremium: sl(),
          findPhotos: sl(),
          restorePhoto: sl(),
          reconcilePhotos: sl(),
          deleteEntry: sl(),
        ),
      )
      // The entry edited (null: a new log) and the weight unit.
      ..registerFactoryParam<WeightFormCubit, BodyEntry?, WeightUnit>(
        (entry, unit) => WeightFormCubit(
          saveEntry: sl(),
          newEntryId: sl(),
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          unit: unit,
          initial: entry,
        ),
      )
      ..registerFactoryParam<MeasurementDayCubit, MeasurementDaySetup, void>(
        (setup, _) => MeasurementDayCubit(
          setup: setup,
          saveEntry: sl(),
          newEntryId: sl(),
          discardCapture: sl(),
          watchEntries: sl(),
          restorePhoto: sl(),
          getCurrentUser: sl(),
          watchAuthUser: sl(),
        ),
      );
  }
}
