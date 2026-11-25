import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/device_details.dart';
import 'data/firestore_device_repository.dart';
import 'domain/device_repository.dart';
import 'domain/devices_usecases.dart';
import 'presentation/device_session.dart';

/// Records the user's devices, with their push tokens, for the admin
/// panel, and clears the push token before every sign-out. Not for the
/// admin panel itself. Needs `AuthModule`, registered before it, and
/// `NotificationsModule` (forge_messaging's `PushTokenSource`).
class DevicesModule implements FeatureModule {
  const DevicesModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<DeviceRepository>(
        () => FirestoreDeviceRepository(
          FirebaseFirestore.instance,
          PlatformDeviceDetails(DeviceInfoPlugin()),
          getApplicationSupportDirectory,
          sl(),
        ),
      )
      ..registerFactory(() => RecordDevice(sl(), DateTime.now))
      ..registerFactory(() => WatchPushTokenChanges(sl()))
      ..registerFactory(() => ForgetPushToken(sl(), DateTime.now))
      // forge_auth's SignOut, swapped before the auth cubits resolve it,
      // so every sign-out first clears this install's push token.
      ..unregister<SignOut>()
      ..registerFactory<SignOut>(
        () => SignOutForgettingPushToken(sl(), sl(), sl()),
      )
      // One for the whole app, created at start (`App`).
      ..registerLazySingleton(
        () => DeviceSession(
          watchAuthUser: sl(),
          recordDevice: sl(),
          watchPushTokenChanges: sl(),
        ),
        dispose: (session) => session.cancel(),
      );
  }
}
