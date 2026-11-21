import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/dashboard.dart';
import '../domain/dashboard_admin_usecases.dart';

/// How the Funnel section shows its steps.
enum FunnelView { bars, table }

/// How the Retention section shows its cohorts.
enum RetentionView { table, curves }

class DashboardState extends Equatable {
  const DashboardState({
    this.data,
    this.loading = true,
    this.failure,
    this.preset = DashboardPreset.days30,
    this.customRange,
    this.customReport,
    this.customLoading = false,
    this.customFailure,
    this.refreshing = false,
    this.refreshFailure,
    this.funnelView = FunnelView.bars,
    this.retentionView = RetentionView.table,
  });

  /// What the nightly refresh stored; null until first loaded.
  final DashboardData? data;
  final bool loading;

  /// Why the last load failed; [data] keeps what was loaded before.
  final Failure? failure;

  /// The stored period shown while no [customRange] is chosen.
  final DashboardPreset preset;

  /// The range chosen with Custom…; null shows [preset].
  final DayRange? customRange;
  final Report? customReport;
  final bool customLoading;
  final Failure? customFailure;

  final bool refreshing;
  final Failure? refreshFailure;

  final FunnelView funnelView;
  final RetentionView retentionView;

  /// The report of the period shown; null while it loads or when there is
  /// none.
  Report? get report =>
      customRange != null ? customReport : data?.reports[preset];

  DashboardState copyWith({
    DashboardData? data,
    bool? loading,
    Failure? Function()? failure,
    DashboardPreset? preset,
    DayRange? Function()? customRange,
    Report? Function()? customReport,
    bool? customLoading,
    Failure? Function()? customFailure,
    bool? refreshing,
    Failure? Function()? refreshFailure,
    FunnelView? funnelView,
    RetentionView? retentionView,
  }) => DashboardState(
    data: data ?? this.data,
    loading: loading ?? this.loading,
    failure: failure != null ? failure() : this.failure,
    preset: preset ?? this.preset,
    customRange: customRange != null ? customRange() : this.customRange,
    customReport: customReport != null ? customReport() : this.customReport,
    customLoading: customLoading ?? this.customLoading,
    customFailure: customFailure != null ? customFailure() : this.customFailure,
    refreshing: refreshing ?? this.refreshing,
    refreshFailure: refreshFailure != null
        ? refreshFailure()
        : this.refreshFailure,
    funnelView: funnelView ?? this.funnelView,
    retentionView: retentionView ?? this.retentionView,
  );

  @override
  List<Object?> get props => [
    data,
    loading,
    failure,
    preset,
    customRange,
    customReport,
    customLoading,
    customFailure,
    refreshing,
    refreshFailure,
    funnelView,
    retentionView,
  ];
}

/// The Dashboard: the stored reports at once, a custom range queried on
/// demand, and a refresh now.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required this._loadDashboard,
    required this._loadRangeReport,
    required this._refreshDashboard,
  }) : super(const DashboardState()) {
    load();
  }

  final LoadDashboard _loadDashboard;
  final LoadRangeReport _loadRangeReport;
  final RefreshDashboard _refreshDashboard;

  /// Reads the stored documents again.
  Future<void> load() async {
    if (!state.loading) emit(state.copyWith(loading: true));
    final result = await _loadDashboard(const NoParams());
    if (isClosed) return;
    emit(
      result.fold(
        (data) =>
            state.copyWith(data: data, loading: false, failure: () => null),
        (failure) => state.copyWith(loading: false, failure: () => failure),
      ),
    );
  }

  /// Shows a stored period.
  void selectPreset(DashboardPreset preset) => emit(
    state.copyWith(
      preset: preset,
      customRange: () => null,
      customReport: () => null,
      customLoading: false,
      customFailure: () => null,
    ),
  );

  /// Shows [range], queried now.
  Future<void> selectRange(DayRange range) async {
    emit(
      state.copyWith(
        customRange: () => range,
        customReport: () => null,
        customLoading: true,
        customFailure: () => null,
      ),
    );
    final result = await _loadRangeReport(range);
    // Another period was chosen meanwhile.
    if (isClosed || state.customRange != range) return;
    emit(
      state.copyWith(
        customReport: () => result.valueOrNull,
        customLoading: false,
        customFailure: () => result.failureOrNull,
      ),
    );
  }

  /// Runs the nightly refresh now, then reads what it stored.
  Future<void> refresh() async {
    if (state.refreshing) return;
    emit(state.copyWith(refreshing: true, refreshFailure: () => null));
    final result = await _refreshDashboard(const NoParams());
    if (isClosed) return;
    emit(
      state.copyWith(
        refreshing: false,
        refreshFailure: () => result.failureOrNull,
      ),
    );
    if (result.isOk) await load();
  }

  void showFunnelAs(FunnelView view) => emit(state.copyWith(funnelView: view));

  void showRetentionAs(RetentionView view) =>
      emit(state.copyWith(retentionView: view));
}
