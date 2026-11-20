import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import 'account_repository.dart';
import 'consent_repository.dart';
import 'sync_repository.dart';

typedef ConsentAnswer = ({String uid, bool consent});

/// Whose account to delete, and the Apple code to revoke their Apple
/// sign-in with, if they have one.
typedef AccountDeletion = ({String uid, String? appleCode});

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

/// Whether this device's writes are all on the server; see
/// [SyncRepository.watchBackedUp].
class WatchBackedUp {
  const WatchBackedUp(this._repository);
  final SyncRepository _repository;

  Stream<bool> call() => _repository.watchBackedUp();
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

/// Holds this device's writes for the user (their photo backup), so
/// none lands after the server deleted their files, and releases them if
/// the deletion did not happen. Then deletes the account on the server,
/// then, still signed in so
/// nothing of the next user is touched, what this device keeps of them,
/// and only then signs out. `account_delete` is logged once the server
/// has deleted the data, before collection for the user stops.
///
/// Once the server has deleted the data the device is cleared even if the
/// sign-in is left ([PartlyDeletedFailure], returned, without signing
/// out, so the user can delete again). A local leftover is logged, not
/// reported: the account is gone.
class DeleteUserAccount implements UseCase<void, AccountDeletion> {
  const DeleteUserAccount(
    this._repository,
    this._local,
    this._telemetry,
    this._analytics,
  );
  final AccountRepository _repository;
  final LocalAccountData _local;
  final Telemetry _telemetry;
  final Analytics _analytics;

  @override
  Future<Result<void>> call(AccountDeletion params) async {
    final uid = params.uid;
    await _local.holdWrites(uid);
    final deleted = await _repository.deleteAccount(
      appleCode: params.appleCode,
    );
    final failure = deleted.failureOrNull;
    if (failure != null && failure is! PartlyDeletedFailure) {
      await _local.releaseWrites(uid);
      return deleted;
    }
    await _analytics.accountDelete();
    for (final cleanup in [_local.clear(uid), _telemetry.forget(uid)]) {
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
