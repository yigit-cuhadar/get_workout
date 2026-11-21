import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/admin_user.dart';
import '../domain/admin_user_repository.dart';

/// Calls the admin-only callables of `functions/src/users/`.
class CallableAdminUserRepository implements AdminUserRepository {
  const CallableAdminUserRepository(this._functions);

  final FirebaseFunctions _functions;

  /// `details.reason` values of the functions' refusals.
  static const _notAdmin = 'not-admin';
  static const _userNotFound = 'user-not-found';
  static const _ownAccount = 'own-account';
  static const _revenueCatFailed = 'revenuecat-failed';
  static const _invalidInput = 'invalid-input';

  /// The server's "never ends" (9999-12-31) and anything later.
  static final _never = DateTime.utc(9999);

  Future<Map<Object?, Object?>> _call(
    String function,
    Map<String, Object?> data,
  ) async {
    final result = await _functions.httpsCallable(function).call<Object?>(data);
    return switch (result.data) {
      final Map<Object?, Object?> map => map,
      null => const {},
      final other => throw UnknownFailure('unexpected result: $other'),
    };
  }

  @override
  Future<Result<UsersPage>> latest({UserCursor? after}) => guard(() async {
    final data = await _call('adminListUsers', {
      if (after != null)
        'cursor': {'createdAtMillis': after.createdAtMillis, 'uid': after.uid},
    });
    final next = data['next'];
    return (
      users: [for (final row in _list(data['users'])) _row(row)],
      next: next is Map
          ? UserCursor(
              createdAtMillis: (next['createdAtMillis'] as num).toInt(),
              uid: '${next['uid']}',
            )
          : null,
    );
  }, mapper: _mapError);

  @override
  Future<Result<String>> find(String query) => guard(
    () async => '${(await _call('adminFindUser', {'query': query}))['uid']}',
    mapper: _mapError,
  );

  @override
  Future<Result<UserDetail>> user(String uid) => guard(
    () async => _detail(await _call('adminGetUser', {'uid': uid})),
    mapper: _mapError,
  );

  @override
  Future<Result<DateTime?>> grantPremium(
    String uid,
    PremiumDuration duration,
  ) => guard(() async {
    final data = await _call('adminGrantPremium', {
      'uid': uid,
      'duration': duration.name,
    });
    return _date(data['expiresAtMillis']);
  }, mapper: _mapError);

  @override
  Future<Result<void>> revokePremium(String uid) =>
      guard(() => _call('adminRevokePremium', {'uid': uid}), mapper: _mapError);

  @override
  Future<Result<void>> setAdmin(String uid, {required bool admin}) => guard(
    () => _call('adminSetAdmin', {'uid': uid, 'admin': admin}),
    mapper: _mapError,
  );

  @override
  Future<Result<void>> delete(String uid) =>
      guard(() => _call('adminDeleteUser', {'uid': uid}), mapper: _mapError);

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch ((error.code, reason)) {
      (_, _notAdmin) => PermissionFailure(message, error),
      (_, _userNotFound) => NotFoundFailure(message, error),
      (_, _ownAccount) => OwnAccountFailure(message, error),
      (_, _invalidInput) => ValidationFailure(message),
      (_, _revenueCatFailed) => RevenueCatFailure(
        message,
        status: switch ((details as Map)['status']) {
          final num status => status.toInt(),
          _ => null,
        },
        cause: error,
      ),
      _ => mapFirebaseError(error),
    };
  }

  static List<Map<Object?, Object?>> _list(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map) item,
  ];

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : const {};

  /// Milliseconds as a date; the server's "never" reads as null.
  static DateTime? _date(Object? millis) {
    if (millis is! num) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(
      millis.toInt(),
      isUtc: true,
    );
    return date.isBefore(_never) ? date : null;
  }

  static String? _text(Object? value) => value is String ? value : null;

  static UserRow _row(Map<Object?, Object?> data) => UserRow(
    uid: '${data['uid']}',
    email: _text(data['email']),
    guest: data['guest'] == true,
    premium: data['premium'] == true,
    signedUp: _date(data['signedUpMillis']) ?? DateTime.utc(1970),
    lastWorkout: _date(data['lastWorkoutMillis']),
  );

  static UserDetail _detail(Map<Object?, Object?> data) {
    final server = data['server'];
    final activity = _map(data['activity']);
    final state = switch (data['revenueCatState']) {
      'ok' => RevenueCatState.ok,
      'no-customer' => RevenueCatState.noCustomer,
      _ => RevenueCatState.failed,
    };
    return UserDetail(
      uid: '${data['uid']}',
      email: _text(data['email']),
      guest: data['guest'] == true,
      providers: [for (final p in data['providers'] as List? ?? const []) '$p'],
      admin: data['admin'] == true,
      signedUp: _date(data['signedUpMillis']) ?? DateTime.utc(1970),
      lastActive: _date(data['lastActiveMillis']),
      server: server is Map
          ? ServerPremium(
              premium: server['premium'] == true,
              expiresAt: _date(server['expiresAtMillis']),
              productId: _text(server['productId']),
              lastChange: _date(server['lastEventMillis']),
            )
          : null,
      workouts: (activity['workouts'] as num? ?? 0).toInt(),
      lastWorkout: _date(activity['lastWorkoutMillis']),
      activeProgram: _text(activity['activeProgram']),
      revenueCat: state == RevenueCatState.ok
          ? _customer(_map(data['revenueCat']))
          : null,
      revenueCatState: state,
    );
  }

  static RevenueCatCustomer _customer(Map<Object?, Object?> data) {
    final premium = data['premium'];
    final seen = _map(data['lastSeen']);
    return RevenueCatCustomer(
      premium: premium is Map,
      premiumEnds: premium is Map ? _date(premium['expiresAtMillis']) : null,
      subscriptions: [
        for (final s in _list(data['subscriptions']))
          StoreSubscription(
            store: '${s['store']}',
            status: '${s['status']}',
            givesAccess: s['givesAccess'] == true,
            productId: _text(s['productId']),
            periodEnds: _date(s['periodEndsAtMillis']),
            autoRenewal: '${s['autoRenewal']}',
          ),
      ],
      lastSeen: LastSeenDevice(
        at: _date(seen['atMillis']),
        platform: _text(seen['platform']),
        platformVersion: _text(seen['platformVersion']),
        appVersion: _text(seen['appVersion']),
      ),
    );
  }
}
