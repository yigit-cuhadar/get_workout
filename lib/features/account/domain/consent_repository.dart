import 'package:forge_core/forge_core.dart';

/// The user's answer to sharing usage statistics and crash reports
/// (`settings.analyticsConsent`).
abstract interface class ConsentRepository {
  /// Null until the user has answered; again on every change. Errors arrive
  /// as [Failure]s.
  Stream<bool?> watchConsent(String uid);

  Future<Result<void>> saveConsent(String uid, bool consent);
}

/// Analytics and crash reporting on this device.
abstract interface class Telemetry {
  /// Collects only with [consent], from now on and from the next launch.
  Future<Result<void>> apply(bool consent);

  /// Drops this device's analytics id and the crash reports not sent yet.
  Future<Result<void>> forget();
}
