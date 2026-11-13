import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_settings_repository.dart';
import 'domain/settings_repository.dart';
import 'domain/settings_usecases.dart';
import 'domain/user_settings.dart';
import 'presentation/settings_cubit.dart';

/// Registers the settings feature. Needs `AuthModule` for the current user.
class SettingsModule implements FeatureModule {
  const SettingsModule();

  @override
  void register(GetIt sl) {
    final defaults = UserSettings.defaultsFor(
      PlatformDispatcher.instance.locale.countryCode,
    );
    sl
      ..registerLazySingleton<SettingsRepository>(
        () => FirestoreSettingsRepository(
          FirebaseFirestore.instance,
          defaults: defaults,
        ),
      )
      ..registerFactory(() => WatchSettings(sl()))
      ..registerFactory(() => UpdateSettings(sl()))
      ..registerFactory(() => MarkTipSeen(sl()))
      ..registerLazySingleton(
        () => SettingsCubit(
          watchAuthUser: sl(),
          watchSettings: sl(),
          updateSettings: sl(),
          markTipSeen: sl(),
          defaults: defaults,
        ),
      );
  }
}
