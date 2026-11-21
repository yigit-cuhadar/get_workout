import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../../app/functions_region.dart';
import 'data/callable_app_settings_repository.dart';
import 'domain/app_settings_repository.dart';
import 'domain/app_settings_usecases.dart';
import 'presentation/app_settings_cubit.dart';

/// Registers the panel's App settings page. Needs the access module's
/// `CheckAdminAccess`.
class AppSettingsAdminModule implements FeatureModule {
  const AppSettingsAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AppSettingsRepository>(
        () => CallableAppSettingsRepository(
          FirebaseFunctions.instanceFor(region: functionsRegion),
        ),
      )
      ..registerFactory(() => LoadAppSettings(sl()))
      ..registerFactory(() => LoadSettingsHistory(sl()))
      ..registerFactory(() => PublishAppSettings(sl()))
      ..registerFactory(
        () => AppSettingsCubit(
          loadAppSettings: sl(),
          loadSettingsHistory: sl(),
          publishAppSettings: sl(),
          checkAdminAccess: sl(),
        ),
      );
  }
}
