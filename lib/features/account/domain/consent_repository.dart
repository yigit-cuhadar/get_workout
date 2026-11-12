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
