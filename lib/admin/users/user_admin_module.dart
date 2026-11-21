import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../../app/functions_region.dart';
import 'data/callable_admin_user_repository.dart';
import 'domain/admin_user_repository.dart';
import 'domain/user_admin_usecases.dart';
import 'presentation/user_cubit.dart';
import 'presentation/users_cubit.dart';

/// Registers the panel's Users pages. Needs forge_auth's `AuthModule` for
/// `SendPasswordReset`.
class UserAdminModule implements FeatureModule {
  const UserAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminUserRepository>(
        () => CallableAdminUserRepository(
          FirebaseFunctions.instanceFor(region: functionsRegion),
        ),
      )
      ..registerFactory(() => ListLatestUsers(sl()))
      ..registerFactory(() => FindUser(sl()))
      ..registerFactory(() => GetAdminUser(sl()))
      ..registerFactory(() => GrantPromotionalPremium(sl()))
      ..registerFactory(() => RevokePromotionalPremium(sl()))
      ..registerFactory(() => SetUserAdmin(sl()))
      ..registerFactory(() => DeleteUserAccount(sl()))
      ..registerFactory(() => UsersCubit(listLatestUsers: sl(), findUser: sl()))
      ..registerFactoryParam<UserCubit, String, void>(
        (uid, _) => UserCubit(
          uid: uid,
          getAdminUser: sl(),
          grantPremium: sl(),
          revokePremium: sl(),
          sendPasswordReset: sl(),
          setUserAdmin: sl(),
          deleteUserAccount: sl(),
        ),
      );
  }
}
