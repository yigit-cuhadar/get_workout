import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_profile_repository.dart';
import 'domain/profile_repository.dart';
import 'domain/profile_usecases.dart';
import 'presentation/profile_cubit.dart';

/// Registers the profile and onboarding. Needs `AuthModule` for the current
/// user, `ExercisesModule`, whose use case saves the equipment, and
/// `BodyModule`, which logs the weight given as the first weigh-in.
class ProfileModule implements FeatureModule {
  const ProfileModule();

  /// Whether [uid] is past onboarding, once their profile has loaded; true
  /// when another user is signed in by then.
  static Future<bool> pastOnboarding(GetIt sl, String uid) async {
    bool settled(ProfileState state) =>
        state.uid != uid || state.status != ProfileStatus.loading;
    final profile = sl<ProfileCubit>();
    final state = settled(profile.state)
        ? profile.state
        : await profile.stream.firstWhere(settled);
    return state.uid != uid || state.pastOnboarding;
  }

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<ProfileRepository>(
        () => FirestoreProfileRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchProfile(sl()))
      ..registerFactory(() => UpdateProfile(sl(), sl()))
      ..registerFactory(() => CompleteOnboarding(sl(), sl(), sl()))
      ..registerLazySingleton(
        () => ProfileCubit(
          watchAuthUser: sl(),
          watchProfile: sl(),
          updateProfile: sl(),
        ),
      );
  }
}
