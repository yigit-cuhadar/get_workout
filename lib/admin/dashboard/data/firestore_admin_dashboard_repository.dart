import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/admin_dashboard_repository.dart';
import '../domain/dashboard.dart';
import 'dashboard_maps.dart';

/// Reads `dashboard`, which only admins may read, and calls the admin-only
/// `dashboardRange` and `dashboardRefresh` (`functions/src/dashboard`).
class FirestoreAdminDashboardRepository implements AdminDashboardRepository {
  const FirestoreAdminDashboardRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  static const rangeFunction = 'dashboardRange';
  static const refreshFunction = 'dashboardRefresh';

  /// The functions' own timeouts; the client's default is one minute.
  static const _rangeTimeout = Duration(seconds: 300);
  static const _refreshTimeout = Duration(seconds: 540);

  /// `details.reason` values of the functions' refusals.
  static const _notAdmin = 'not-admin';
  static const _invalidInput = 'invalid-input';
  static const _noData = 'no-data';

  @override
  Future<Result<DashboardData>> load() => guard(() async {
    final docs = {
      for (final doc in (await _firestore.collection('dashboard').get()).docs)
        doc.id: doc.data(),
    };
    return DashboardData(
      status: _parse(docs['status'], DashboardMaps.status),
      reports: {
        for (final preset in DashboardPreset.values)
          preset: ?_parse(docs['p${preset.days}'], DashboardMaps.report),
      },
      retention: _parse(docs['retention'], DashboardMaps.retention),
      revenue: _parse(docs['revenue'], DashboardMaps.revenue),
    );
  }, mapper: mapFirebaseError);

  @override
  Future<Result<Report>> report(DayRange range) => guard(() async {
    final result = await _functions
        .httpsCallable(
          rangeFunction,
          options: HttpsCallableOptions(timeout: _rangeTimeout),
        )
        .call<Object?>({
          'from': DashboardMaps.dayString(range.from),
          'to': DashboardMaps.dayString(range.to),
        });
    final data = result.data;
    if (data is! Map) throw UnknownFailure('unexpected result: $data');
    return DashboardMaps.report(data);
  }, mapper: _mapError);

  @override
  Future<Result<DashboardStatus>> refresh() => guard(() async {
    final result = await _functions
        .httpsCallable(
          refreshFunction,
          options: HttpsCallableOptions(timeout: _refreshTimeout),
        )
        .call<Object?>();
    final data = result.data;
    if (data is! Map) throw UnknownFailure('unexpected result: $data');
    return DashboardMaps.status(data);
  }, mapper: _mapError);

  static T? _parse<T>(
    Map<String, Object?>? data,
    T Function(Map<Object?, Object?>) parse,
  ) => data == null ? null : parse(data);

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    return switch (details is Map ? details['reason'] : null) {
      _notAdmin => PermissionFailure(message, error),
      _invalidInput => ValidationFailure(message),
      _noData => DashboardNoDataFailure(message),
      _ => mapFirebaseError(error),
    };
  }
}
