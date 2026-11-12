import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../workout/presentation/active_workout_cubit.dart';
import 'data/callable_account_repository.dart';
import 'data/device_account_data.dart';
import 'data/firebase_telemetry.dart';
import 'data/firestore_consent_repository.dart';
import 'domain/account_repository.dart';
import 'domain/account_usecases.dart';
import 'domain/consent_repository.dart';
import 'presentation/consent_cubit.dart';
import 'presentation/delete_account_cubit.dart';

/// Registers analytics consent and account deletion. Needs `AuthModule`,
/// `NotificationsModule`, `WorkoutModule` and `BodyModule` (whose kept
/// workouts and photos deletion removes), and the [telemetry] started by [startTelemetry].
class AccountModule implements FeatureModule {
  const AccountModule({required this.telemetry});

  final FirebaseTelemetry telemetry;

  /// Call right after `Firebase.initializeApp`, before anything uses
  /// Firestore: removes the offline copy a deleted account left.
  static Future<void> clearDeletedAccountCache() =>
      DeviceAccountData.clearOfflineCopyIfMarked(
        getApplicationSupportDirectory,
        FirebaseFirestore.instance,
      );

  /// Call right after `Firebase.initializeApp`, in place of
  /// `forge_firebase`'s `initFirebase`: collection follows the answer the
  /// signed-in user last gave on this device, until their stored one is
  /// read.
  static Future<FirebaseTelemetry> startTelemetry(AppEnv env) async {
    final telemetry = FirebaseTelemetry(
      allowed: env.isProd && kReleaseMode,
      directory: getApplicationSupportDirectory,
      analytics: FirebaseAnalytics.instance,
      crashlytics: FirebaseCrashlytics.instance,
    );
    await telemetry.start(FirebaseAuth.instance.currentUser?.uid);
    return telemetry;
  }

  @override
  void register(GetIt sl) {
    sl
      ..registerSingleton<Telemetry>(telemetry)
      ..registerLazySingleton<ConsentRepository>(
        () => FirestoreConsentRepository(FirebaseFirestore.instance),
      )
      ..registerLazySingleton<AccountRepository>(
        () => CallableAccountRepository(
          FirebaseFunctions.instanceFor(
            region: CallableAccountRepository.region,
          ),
          FirebaseAuth.instance,
          FirebaseFirestore.instance,
        ),
      )
      ..registerLazySingleton<LocalAccountData>(
        () => DeviceAccountData(
          sl(),
          sl.getAsync<Notifications>(),
          getApplicationSupportDirectory,
          stopPhotoBackup: sl(),
          resumePhotoBackup: sl(),
          forgetPhotos: sl(),
        ),
      )
      ..registerFactory(() => WatchAnalyticsConsent(sl()))
      ..registerFactory(() => SaveAnalyticsConsent(sl()))
      ..registerFactory(() => FollowAnalyticsUser(sl()))
      ..registerFactory(() => ApplyAnalyticsConsent(sl()))
      ..registerLazySingleton(DeletionUnderway.new)
      ..registerFactory(() => Reauthenticate(sl()))
      ..registerFactory(() => DeleteUserAccount(sl(), sl(), sl()))
      ..registerLazySingleton(
        () => ConsentCubit(
          watchAuthUser: sl(),
          watchConsent: sl(),
          saveConsent: sl(),
          followUser: sl(),
          applyConsent: sl(),
        ),
      )
      ..registerFactory(
        () => DeleteAccountCubit(
          getCurrentUser: sl(),
          deleteAccount: sl(),
          reauthenticate: sl(),
          underway: sl(),
          releaseWorkouts: sl<ActiveWorkoutCubit>().releaseUser,
          resumeWorkouts: sl<ActiveWorkoutCubit>().resumeUser,
        ),
      );
  }
}
