import 'package:forge_core/forge_core.dart';

import 'dashboard.dart';

/// The Dashboard's numbers: what the nightly refresh stored in
/// `dashboard`, and the admin-only functions for a custom range and a
/// refresh now.
abstract interface class AdminDashboardRepository {
  /// The stored status, preset reports, retention and revenue.
  Future<Result<DashboardData>> load();

  /// The report of [range], queried now; [DashboardNoDataFailure] before
  /// the first export, [ValidationFailure] for a range the server refuses.
  Future<Result<Report>> report(DayRange range);

  /// Runs the nightly refresh now and answers with its status.
  Future<Result<DashboardStatus>> refresh();
}
