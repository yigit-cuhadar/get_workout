import 'package:forge_core/forge_core.dart';
import 'package:intl/intl.dart';

import '../../shell/admin_text.dart';
import '../domain/dashboard.dart';

/// What stands for an unknown number.
const unknown = '—';

final _day = DateFormat('yyyy-MM-dd');
final _shortDay = DateFormat('MMM d');
final _count = NumberFormat('#,##0.#');
final _share = NumberFormat('0.#');

String dayLabel(DateTime day) => _day.format(day);

String shortDayLabel(DateTime day) => _shortDay.format(day);

String countLabel(num? value) => value == null ? unknown : _count.format(value);

/// A share from 0 to 1 as a percentage.
String shareLabel(double? value) =>
    value == null ? unknown : '${_share.format(value * 100)}%';

/// RevenueCat reports in USD when it does not say.
String moneyLabel(double? value, String? currency) => value == null
    ? unknown
    : NumberFormat.simpleCurrency(name: currency ?? 'USD').format(value);

String tileLabel(DashboardTile tile) => switch (tile) {
  DashboardTile.dailyActiveUsers => 'Daily active users',
  DashboardTile.monthlyActiveUsers => 'Monthly active users',
  DashboardTile.newUsers => 'New users',
  DashboardTile.onboardingCompleted => 'Onboarding completed',
  DashboardTile.firstWorkout => 'First workout',
  DashboardTile.workoutsCompleted => 'Workouts completed',
  DashboardTile.trialStarts => 'Trial starts',
  DashboardTile.paidConversion => 'Paid conversion',
  DashboardTile.mrr => 'MRR',
  DashboardTile.crashFreeUsers => 'Crash-free users',
};

/// Whether the tile is a share of users, compared in points.
bool _isShare(DashboardTile tile) => switch (tile) {
  DashboardTile.onboardingCompleted ||
  DashboardTile.firstWorkout ||
  DashboardTile.paidConversion ||
  DashboardTile.crashFreeUsers => true,
  _ => false,
};

String tileFigure(DashboardTile tile, double? value, {String? currency}) =>
    switch (tile) {
      DashboardTile.mrr => moneyLabel(value, currency),
      _ when _isShare(tile) => shareLabel(value),
      _ => countLabel(value),
    };

/// The change against the period before: "▲ 8%" for a count, "▲ 2 pts"
/// for a share; [good] when it rose (higher is better for every tile),
/// null when it held. Null when either side is unknown, or a count rose
/// from zero.
({String text, bool? good})? tileChange(DashboardTile tile, TileValue tv) {
  final value = tv.value;
  final previous = tv.previous;
  if (value == null || previous == null) return null;
  final String amount;
  final double rounded;
  if (_isShare(tile)) {
    rounded = double.parse(((value - previous) * 100).toStringAsFixed(1));
    amount = '${_share.format(rounded.abs())} pts';
  } else {
    if (previous == 0) return value == 0 ? (text: '0%', good: null) : null;
    rounded = ((value - previous) / previous * 100).roundToDouble();
    amount = '${rounded.abs().toStringAsFixed(0)}%';
  }
  if (rounded == 0) return (text: amount, good: null);
  return rounded > 0
      ? (text: '▲ $amount', good: true)
      : (text: '▼ $amount', good: false);
}

String dashboardFailureText(Failure failure) => switch (failure) {
  DashboardNoDataFailure() =>
    'No Analytics data yet: the first export arrives within a day of linking.',
  ValidationFailure(:final message) => message,
  NotFoundFailure() =>
    'The dashboard functions are not deployed on this project.',
  _ => failureMessage(failure),
};
