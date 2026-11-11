import 'package:firebase_auth/firebase_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firebase_admin_access_repository.dart';
import 'domain/access_usecases.dart';
import 'domain/admin_access_repository.dart';
import 'presentation/access_cubit.dart';

/// Registers the panel's access gate. Needs `AuthModule`.
class AdminAccessModule implements FeatureModule {
  const AdminAccessModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminAccessRepository>(
        () => FirebaseAdminAccessRepository(FirebaseAuth.instance),
      )
      ..registerFactory(() => CheckAdminAccess(sl()))
      ..registerLazySingleton(
        () => AccessCubit(
          watchAuthUser: sl(),
          checkAdminAccess: sl(),
          signOut: sl(),
        ),
      );
  }
}
