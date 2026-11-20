import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_admin_feedback_repository.dart';
import 'domain/admin_feedback_repository.dart';
import 'domain/feedback_admin_usecases.dart';
import 'presentation/feedback_admin_cubit.dart';

/// Registers the panel's feedback page.
class FeedbackAdminModule implements FeatureModule {
  const FeedbackAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminFeedbackRepository>(
        () => FirestoreAdminFeedbackRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchFeedback(sl()))
      ..registerFactory(() => SetFeedbackStatus(sl()))
      ..registerFactory(
        () => FeedbackAdminCubit(watchFeedback: sl(), setFeedbackStatus: sl()),
      );
  }
}
