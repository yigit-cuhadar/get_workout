import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/device_details.dart';
import 'data/firestore_device_repository.dart';
import 'domain/device_repository.dart';
import 'domain/devices_usecases.dart';
import 'presentation/device_session.dart';

/// Records the user's devices for the admin panel. Not for the admin
/// panel itself. Needs `AuthModule`.
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
        ),
      )
      ..registerFactory(() => RecordDevice(sl(), DateTime.now))
      // One for the whole app, created at start (`App`).
      ..registerLazySingleton(
        () => DeviceSession(watchAuthUser: sl(), recordDevice: sl()),
        dispose: (session) => session.cancel(),
      );
  }
}
