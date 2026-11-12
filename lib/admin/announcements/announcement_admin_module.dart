import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../../app/functions_region.dart';
import 'data/callable_admin_announcement_repository.dart';
import 'domain/admin_announcement_repository.dart';
import 'domain/announcement_admin_usecases.dart';
import 'presentation/announcements_cubit.dart';

/// Registers the panel's announcements page. Needs the access module's
/// `CheckAdminAccess`.
class AnnouncementAdminModule implements FeatureModule {
  const AnnouncementAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminAnnouncementRepository>(
        () => CallableAdminAnnouncementRepository(
          FirebaseFunctions.instanceFor(region: functionsRegion),
          FirebaseFirestore.instance,
        ),
      )
      ..registerFactory(() => WatchAnnouncements(sl()))
      ..registerFactory(() => SendAnnouncement(sl()))
      ..registerFactory(
        () => AnnouncementsCubit(
          watchAnnouncements: sl(),
          sendAnnouncement: sl(),
          checkAdminAccess: sl(),
        ),
      );
  }
}
