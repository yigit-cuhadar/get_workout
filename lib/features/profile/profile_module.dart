import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_profile_repository.dart';
import 'domain/profile_repository.dart';
import 'domain/profile_usecases.dart';
import 'presentation/profile_cubit.dart';

/// Registers the profile and onboarding. Needs `AuthModule` for the current
/// user.
class ProfileModule implements FeatureModule {
  const ProfileModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<ProfileRepository>(
        () => FirestoreProfileRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchProfile(sl()))
      ..registerFactory(() => UpdateProfile(sl()))
      ..registerFactory(() => CompleteOnboarding(sl()))
      ..registerLazySingleton(
        () => ProfileCubit(watchAuthUser: sl(), watchProfile: sl()),
      );
  }
}
