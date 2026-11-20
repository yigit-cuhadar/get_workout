import 'package:forge_core/forge_core.dart';

import 'admin_dashboard_repository.dart';
import 'dashboard.dart';

class LoadDashboard implements UseCase<DashboardData, NoParams> {
  const LoadDashboard(this._repository);
  final AdminDashboardRepository _repository;

  @override
  Future<Result<DashboardData>> call(NoParams params) => _repository.load();
}

/// The report of a custom range, or a [ValidationFailure] without asking
/// the server for a range longer than [maxDays].
class LoadRangeReport implements UseCase<Report, DayRange> {
  const LoadRangeReport(this._repository);
  final AdminDashboardRepository _repository;

  /// `MAX_RANGE_DAYS` in `functions/src/dashboard/dashboard_range.ts`.
  static const maxDays = 366;

  @override
  Future<Result<Report>> call(DayRange params) async {
    if (params.days < 1 || params.days > maxDays) {
      return const Err(
        ValidationFailure('A range has from 1 to $maxDays days.'),
      );
    }
    return _repository.report(params);
  }
}

class RefreshDashboard implements UseCase<DashboardStatus, NoParams> {
  const RefreshDashboard(this._repository);
  final AdminDashboardRepository _repository;

  @override
  Future<Result<DashboardStatus>> call(NoParams params) =>
      _repository.refresh();
}
