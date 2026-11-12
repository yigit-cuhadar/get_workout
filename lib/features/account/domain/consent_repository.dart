import 'package:forge_core/forge_core.dart';

/// A user's stored answer to sharing usage statistics and crash reports
/// (`settings.analyticsConsent`): null until they answered. Only an answer
/// [fromServer] tells that a missing one is really missing; a cached copy
/// may predate an answer given on another device.
typedef StoredConsent = ({bool? consent, bool fromServer});

abstract interface class ConsentRepository {
  /// Again on every change. Errors arrive as [Failure]s.
  Stream<StoredConsent> watchConsent(String uid);

  Future<Result<void>> saveConsent(String uid, bool consent);
}

/// Analytics and crash reporting on this device. Collection is per user,
/// never per device: it follows one user's own answer, and is off while
/// that is unknown.
abstract interface class Telemetry {
  /// From now on collection follows [uid] (null: nobody). Another user than
  /// before turns it off until [apply] gives their answer.
  Future<Result<void>> follow(String? uid);

  /// Collects for [uid] only with [consent], from now on and when the app
  /// next starts with them signed in. Of quick answers the latest wins.
  Future<Result<void>> apply(String uid, bool consent);

  /// After [uid]'s account is deleted: records no for them, stops
  /// collecting, and drops this device's analytics id and unsent crash
  /// reports.
  Future<Result<void>> forget(String uid);
}
