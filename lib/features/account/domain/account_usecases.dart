import 'package:forge_core/forge_core.dart';

import 'account_repository.dart';
import 'consent_repository.dart';

typedef ConsentAnswer = ({String uid, bool consent});

class WatchAnalyticsConsent {
  const WatchAnalyticsConsent(this._repository);
  final ConsentRepository _repository;

  Stream<StoredConsent> call(String uid) => _repository.watchConsent(uid);
}

class SaveAnalyticsConsent implements UseCase<void, ConsentAnswer> {
  const SaveAnalyticsConsent(this._repository);
  final ConsentRepository _repository;

  @override
  Future<Result<void>> call(ConsentAnswer params) =>
      _repository.saveConsent(params.uid, params.consent);
}

/// Points collection at the signed-in user (null: nobody); off until
/// [ApplyAnalyticsConsent] gives their answer.
class FollowAnalyticsUser implements UseCase<void, String?> {
  const FollowAnalyticsUser(this._telemetry);
  final Telemetry _telemetry;

  @override
  Future<Result<void>> call(String? params) => _telemetry.follow(params);
}

class ApplyAnalyticsConsent implements UseCase<void, ConsentAnswer> {
  const ApplyAnalyticsConsent(this._telemetry);
  final Telemetry _telemetry;

  @override
  Future<Result<void>> call(ConsentAnswer params) =>
      _telemetry.apply(params.uid, params.consent);
}

class Reauthenticate implements UseCase<void, String> {
  const Reauthenticate(this._repository);
  final AccountRepository _repository;

  @override
  Future<Result<void>> call(String params) =>
      _repository.reauthenticate(params);
}

/// Holds this device's writes for user [String] (their photo backup), so
/// none lands after the server deleted their files, and releases them if
/// the deletion did not happen. Then deletes the account on the server,
/// then, still signed in so
/// nothing of the next user is touched, what this device keeps of them,
/// and only then signs out.
///
/// Once the server has deleted the data the device is cleared even if the
/// sign-in is left ([PartlyDeletedFailure], returned, without signing
/// out, so the user can delete again). A local leftover is logged, not
/// reported: the account is gone.
class DeleteUserAccount implements UseCase<void, String> {
  const DeleteUserAccount(this._repository, this._local, this._telemetry);
  final AccountRepository _repository;
  final LocalAccountData _local;
  final Telemetry _telemetry;

  @override
  Future<Result<void>> call(String params) async {
    await _local.holdWrites(params);
    final deleted = await _repository.deleteAccount();
    final failure = deleted.failureOrNull;
    if (failure != null && failure is! PartlyDeletedFailure) {
      await _local.releaseWrites(params);
      return deleted;
    }
    for (final cleanup in [_local.clear(params), _telemetry.forget(params)]) {
      _logLeftover(await cleanup);
    }
    if (failure != null) return deleted;
    _logLeftover(await _repository.signOut());
    return const Ok(null);
  }

  static void _logLeftover(Result<void> result) {
    if (result.failureOrNull case final failure?) {
      Log.e('account', 'left after deletion: ${failure.message}');
    }
  }
}
