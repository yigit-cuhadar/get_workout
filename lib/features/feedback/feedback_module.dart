import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_review/forge_review.dart';
import 'package:get_it/get_it.dart';

import '../../core/device_details.dart';
import 'data/firestore_feedback_repository.dart';
import 'domain/feedback.dart';
import 'domain/feedback_repository.dart';
import 'domain/feedback_usecases.dart';
import 'presentation/feedback_cubit.dart';

/// Registers the feedback form. Needs `AuthModule` for the current user.
class FeedbackModule implements FeatureModule {
  const FeedbackModule();

  /// When the review prompt asks: first after the second finished workout
  /// or on the third different day the app is opened, whichever comes
  /// first; later after a workout with a new record at least 30 days on;
  /// once per version.
  static const reviewRules = ReviewRules(
    firstAfterEvents: 2,
    firstAfterDays: 3,
    cooldown: Duration(days: 30),
  );

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<FeedbackRepository>(
        () => FirestoreFeedbackRepository(
          FirebaseFirestore.instance,
          PlatformDeviceDetails(DeviceInfoPlugin()),
        ),
      )
      ..registerFactory(() => SendFeedback(sl()))
      ..registerFactoryParam<FeedbackCubit, FeedbackSource, void>(
        (source, _) => FeedbackCubit(
          sendFeedback: sl(),
          getCurrentUser: sl(),
          source: source,
          analytics: sl(),
        ),
      );
  }
}
