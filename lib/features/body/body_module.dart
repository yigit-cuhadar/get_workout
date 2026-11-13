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
import 'data/file_body_chart_store.dart';
import 'data/file_body_photo_store.dart';
import 'data/firestore_body_repository.dart';
import 'data/storage_body_photo_backup.dart';
import 'domain/body_entry.dart';
import 'domain/body_chart.dart';
import 'domain/body_photo_sync.dart';
import 'domain/body_photos.dart';
import 'domain/body_repository.dart';
import 'domain/body_usecases.dart';
import 'domain/measurement_summary.dart';
import 'presentation/body_chart_cubit.dart';
import 'presentation/body_list_cubit.dart';
import 'presentation/measurement_day_cubit.dart';
import 'presentation/measurement_summary_cubit.dart';
import 'presentation/weight_form_cubit.dart';

/// Registers the weight log and measurement days. Needs `AuthModule` for
/// the current user, `ProgramsModule` for `WatchPremium`, `ProfileModule`,
/// whose use cases keep the profile weight and give the sex and height for
/// body fat, and for the chart `VolumeModule`, `StepsModule` and
/// `HealthModule`.
class BodyModule implements FeatureModule {
  const BodyModule();

  static const _retryTime = Duration(minutes: 1);

  /// Starts backing up photos for whoever signs in; call once the app is
  /// up, and [resumed] whenever it returns to the foreground.
  static void startPhotoBackup(GetIt sl) => sl<BodyPhotoSync>().start(
    sl<WatchAuthUser>()().map(
      (user) => user == null ? null : (id: user.id, guest: user.isAnonymous),
    ),
  );

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
      ..registerLazySingleton(() => BodyPhotoSync(sl(), sl(), sl(), sl()))
      ..registerLazySingleton<BodyChartStore>(
        () => const FileBodyChartStore(getApplicationSupportDirectory),
      )
      ..registerFactory(() => LoadBodyChart(sl()))
      ..registerFactory(() => SaveBodyChart(sl()))
      ..registerFactory(() => WatchBodyEntries(sl()))
      // For the measurement reminders.
      ..registerFactory(() => WatchMeasuredDates(sl()))
      ..registerFactory(() => WatchRejectedBodyWrites(sl()))
      ..registerFactory(() => NewBodyEntryId(sl()))
      ..registerFactory(() => FindBodyPhotos(sl()))
      ..registerFactory(() => RestoreBodyPhoto(sl()))
      ..registerFactory(() => ReconcileBodyPhotos(sl()))
      ..registerFactory(() => DiscardCapture(sl()))
      // For the account feature's deletion.
      ..registerFactory(() => StopBodyPhotoBackup(sl()))
      ..registerFactory(() => ResumeBodyPhotoBackup(sl()))
      ..registerFactory(() => ForgetBodyPhotos(sl()))
      ..registerFactory(() => SyncProfileWeight(sl(), sl(), sl()))
      ..registerFactory(() => SaveBodyEntry(sl(), sl(), sl(), sl()))
      ..registerFactory(() => DeleteBodyEntry(sl(), sl(), sl(), sl()))
      ..registerFactory(() => const FindBaseline())
      // One list for the whole app: every body page shares it.
      ..registerLazySingleton(
        () => BodyListCubit(
          watchAuthUser: sl(),
          watchEntries: sl(),
          watchRejectedWrites: sl(),
          watchPremium: sl(),
          watchProfile: sl(),
          findPhotos: sl(),
          restorePhoto: sl(),
          reconcilePhotos: sl(),
          deleteEntry: sl(),
        ),
      )
      // One per Body page; the parameter is the locale's first weekday.
      ..registerFactoryParam<BodyChartCubit, int, void>(
        (firstWeekday, _) => BodyChartCubit(
          firstWeekday: firstWeekday,
          body: sl(),
          watchAuthUser: sl(),
          watchPremium: sl(),
          loadChoice: sl(),
          saveChoice: sl(),
          watchVolume: sl(),
          getStepsAccess: sl(),
          getDailySteps: sl(),
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
      // The id of the entry summed up; null to choose it, the newest
      // comparable by default.
      ..registerFactoryParam<MeasurementSummaryCubit, String?, void>(
        (id, _) => MeasurementSummaryCubit(
          afterId: id,
          watchAuthUser: sl(),
          watchEntries: sl(),
          watchProfile: sl(),
          findBaseline: sl(),
          restorePhoto: sl(),
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
