import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'domain/analytics.dart';
import 'presentation/analytics_session.dart';

/// Registers the app's analytics over the `Telemetry` of `AccountModule`,
/// and the session that keeps the user properties current. The session
/// needs `AuthModule`, `ProfileModule`, `ProgramsModule` and
/// `SubscriptionModule`.
class AnalyticsModule implements FeatureModule {
  const AnalyticsModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton(() => Analytics(sl()))
      ..registerLazySingleton(
        () => AnalyticsSession(
          watchAuthUser: sl(),
          profile: sl(),
          entitlement: sl(),
          programs: sl(),
          analytics: sl(),
        ),
        dispose: (session) => session.cancel(),
      );
  }
}
