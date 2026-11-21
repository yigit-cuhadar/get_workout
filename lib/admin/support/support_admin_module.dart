import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../../app/functions_region.dart';
import 'data/firestore_support_inbox_repository.dart';
import 'domain/support_inbox_repository.dart';
import 'domain/support_inbox_usecases.dart';
import 'presentation/new_thread_count_cubit.dart';
import 'presentation/support_inbox_cubit.dart';
import 'presentation/support_thread_cubit.dart';

/// Registers the panel's Support inbox and the menu's count of New threads.
class SupportAdminModule implements FeatureModule {
  const SupportAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<SupportInboxRepository>(
        () => FirestoreSupportInboxRepository(
          FirebaseFirestore.instance,
          FirebaseFunctions.instanceFor(region: functionsRegion),
        ),
      )
      ..registerFactory(() => WatchThreads(sl()))
      ..registerFactory(() => WatchNewThreadCount(sl()))
      ..registerFactory(() => WatchReplies(sl()))
      ..registerFactory(() => CloseThread(sl()))
      ..registerFactory(() => ReopenThread(sl()))
      ..registerFactory(() => SendReply(sl()))
      ..registerFactory(
        () => SupportInboxCubit(
          watchThreads: sl(),
          closeThread: sl(),
          reopenThread: sl(),
        ),
      )
      ..registerFactoryParam<SupportThreadCubit, String, void>(
        (threadPath, _) => SupportThreadCubit(
          threadPath: threadPath,
          watchReplies: sl(),
          sendReply: sl(),
        ),
      )
      ..registerFactory(() => NewThreadCountCubit(watchNewThreadCount: sl()));
  }
}
