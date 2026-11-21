import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../../app/functions_region.dart';
import 'data/firestore_admin_dashboard_repository.dart';
import 'domain/admin_dashboard_repository.dart';
import 'domain/dashboard_admin_usecases.dart';
import 'presentation/dashboard_cubit.dart';

/// Registers the panel's Dashboard page.
class DashboardAdminModule implements FeatureModule {
  const DashboardAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminDashboardRepository>(
        () => FirestoreAdminDashboardRepository(
          FirebaseFirestore.instance,
          FirebaseFunctions.instanceFor(region: functionsRegion),
        ),
      )
      ..registerFactory(() => LoadDashboard(sl()))
      ..registerFactory(() => LoadRangeReport(sl()))
      ..registerFactory(() => RefreshDashboard(sl()))
      ..registerFactory(
        () => DashboardCubit(
          loadDashboard: sl(),
          loadRangeReport: sl(),
          refreshDashboard: sl(),
        ),
      );
  }
}
