import 'package:forge_core/forge_core.dart';

import 'account_repository.dart';
import 'consent_repository.dart';

typedef ConsentAnswer = ({String uid, bool consent});

class WatchAnalyticsConsent {
  const WatchAnalyticsConsent(this._repository);
  final ConsentRepository _repository;

  Stream<bool?> call(String uid) => _repository.watchConsent(uid);
}

class SaveAnalyticsConsent implements UseCase<void, ConsentAnswer> {
  const SaveAnalyticsConsent(this._repository);
  final ConsentRepository _repository;

  @override
  Future<Result<void>> call(ConsentAnswer params) =>
      _repository.saveConsent(params.uid, params.consent);
}

/// Collects only after a yes; not answered yet is no.
class ApplyAnalyticsConsent implements UseCase<void, bool?> {
  const ApplyAnalyticsConsent(this._telemetry);
  final Telemetry _telemetry;

  @override
  Future<Result<void>> call(bool? params) => _telemetry.apply(params ?? false);
}

class Reauthenticate implements UseCase<void, String> {
  const Reauthenticate(this._repository);
  final AccountRepository _repository;

  @override
  Future<Result<void>> call(String params) =>
      _repository.reauthenticate(params);
}

/// Deletes user [String]'s account on the server, which also ends the
/// session here, then what this device keeps of them. Once the server has
/// deleted it the deletion counts as done: a local leftover is logged, not
/// reported.
class DeleteUserAccount implements UseCase<void, String> {
  const DeleteUserAccount(this._repository, this._local, this._telemetry);
  final AccountRepository _repository;
  final LocalAccountData _local;
  final Telemetry _telemetry;

  @override
  Future<Result<void>> call(String params) async {
    final deleted = await _repository.deleteAccount();
    if (!deleted.isOk) return deleted;
    for (final cleanup in [_local.clear(params), _telemetry.forget()]) {
      if ((await cleanup).failureOrNull case final failure?) {
        Log.e('account', 'left on the device: ${failure.message}');
      }
    }
    return const Ok(null);
  }
}
