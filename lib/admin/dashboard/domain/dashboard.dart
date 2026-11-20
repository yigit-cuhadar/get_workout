import 'package:forge_core/forge_core.dart';

/// The stored periods, `dashboard/p<days>`, each ending at the latest day
/// with Analytics data.
enum DashboardPreset {
  days7(7),
  days30(30),
  days90(90);

  const DashboardPreset(this.days);
  final int days;
}

/// An inclusive range of days; each end is a UTC midnight.
class DayRange extends Equatable {
  const DayRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// The number of days, both ends included.
  int get days => to.difference(from).inDays + 1;

  @override
  List<Object?> get props => [from, to];
}

/// The ten figures on top of the page, in order; the names are the keys
/// of a report's `tiles`. For every one of them higher is better.
enum DashboardTile {
  dailyActiveUsers,
  monthlyActiveUsers,
  newUsers,
  onboardingCompleted,
  firstWorkout,
  workoutsCompleted,
  trialStarts,
  paidConversion,
  mrr,
  crashFreeUsers,
}

/// A figure of the period and of the equally long period before it; either
/// is null when unknown. Shares are from 0 to 1.
class TileValue extends Equatable {
  const TileValue({this.value, this.previous});

  final double? value;
  final double? previous;

  @override
  List<Object?> get props => [value, previous];
}

/// Active and new users of one day.
class DayCount extends Equatable {
  const DayCount({required this.day, this.active, this.newUsers});

  final DateTime day;
  final int? active;
  final int? newUsers;

  @override
  List<Object?> get props => [day, active, newUsers];
}

/// The period's new users, and how many of them reached each step.
class Funnel extends Equatable {
  const Funnel({
    this.installed,
    this.onboardingComplete,
    this.firstWorkout,
    this.paywallSeen,
    this.trialStarted,
    this.paid,
  });

  final int? installed;
  final int? onboardingComplete;
  final int? firstWorkout;
  final int? paywallSeen;
  final int? trialStarted;
  final int? paid;

  @override
  List<Object?> get props => [
    installed,
    onboardingComplete,
    firstWorkout,
    paywallSeen,
    trialStarted,
    paid,
  ];
}

class Usage extends Equatable {
  const Usage({
    this.programStarts,
    this.workoutsPerActiveUser,
    this.customExercisesCreated,
    this.weightsLogged,
    this.notificationsOpened,
    this.topProgramId,
    this.topProgramStarts,
  });

  final int? programStarts;
  final double? workoutsPerActiveUser;
  final int? customExercisesCreated;
  final int? weightsLogged;
  final int? notificationsOpened;

  /// The ready-made program started most often; null when none was.
  final String? topProgramId;
  final int? topProgramStarts;

  @override
  List<Object?> get props => [
    programStarts,
    workoutsPerActiveUser,
    customExercisesCreated,
    weightsLogged,
    notificationsOpened,
    topProgramId,
    topProgramStarts,
  ];
}

/// A Crashlytics issue and how many installations it reached.
class Issue extends Equatable {
  const Issue({required this.title, this.users});

  final String title;
  final int? users;

  @override
  List<Object?> get props => [title, users];
}

/// Crashlytics in the period; all null when there is no Crashlytics data.
class Quality extends Equatable {
  const Quality({this.crashFreeUsers, this.handledErrors, this.topIssues});

  final double? crashFreeUsers;
  final int? handledErrors;
  final List<Issue>? topIssues;

  @override
  List<Object?> get props => [crashFreeUsers, handledErrors, topIssues];
}

/// Every metric of a period (`functions/src/dashboard/report.ts`).
class Report extends Equatable {
  const Report({
    required this.range,
    required this.tiles,
    required this.growth,
    required this.funnel,
    required this.usage,
    required this.quality,
  });

  /// Null when the report did not say.
  final DayRange? range;
  final Map<DashboardTile, TileValue> tiles;

  /// One entry per day, in order.
  final List<DayCount> growth;
  final Funnel funnel;
  final Usage usage;
  final Quality quality;

  @override
  List<Object?> get props => [range, tiles, growth, funnel, usage, quality];
}

/// A weekly install cohort; a day-N share (0 to 1) is null until known.
class Cohort extends Equatable {
  const Cohort({required this.week, this.users, this.d1, this.d7, this.d30});

  /// The week's Monday.
  final DateTime week;
  final int? users;
  final double? d1;
  final double? d7;
  final double? d30;

  @override
  List<Object?> get props => [week, users, d1, d7, d30];
}

/// RevenueCat's overview metrics, independent of the period; money in
/// [currency].
class RevenueSnapshot extends Equatable {
  const RevenueSnapshot({
    this.mrr,
    this.revenue28d,
    this.activeSubscriptions,
    this.activeTrials,
    this.currency,
  });

  final double? mrr;
  final double? revenue28d;
  final int? activeSubscriptions;
  final int? activeTrials;

  /// An ISO 4217 code; null when the snapshot did not say.
  final String? currency;

  @override
  List<Object?> get props => [
    mrr,
    revenue28d,
    activeSubscriptions,
    activeTrials,
    currency,
  ];
}

/// How the last refresh went; [unknown] for a state this panel does not
/// know.
enum RefreshState { ok, noData, error, unknown }

/// `dashboard/status`.
class DashboardStatus extends Equatable {
  const DashboardStatus({
    required this.state,
    this.lastDay,
    this.updatedAt,
    this.message,
  });

  final RefreshState state;

  /// The latest day with Analytics data; null before the first export.
  final DateTime? lastDay;
  final DateTime? updatedAt;

  /// The parts that failed, when any did.
  final String? message;

  @override
  List<Object?> get props => [state, lastDay, updatedAt, message];
}

/// Everything the nightly refresh stores; a part is null while it has
/// never been stored.
class DashboardData extends Equatable {
  const DashboardData({
    this.status,
    this.reports = const {},
    this.retention,
    this.revenue,
  });

  final DashboardStatus? status;
  final Map<DashboardPreset, Report> reports;
  final List<Cohort>? retention;
  final RevenueSnapshot? revenue;

  /// Nothing to show before the first Analytics export.
  bool get hasNoData =>
      reports.isEmpty &&
      (status == null || status!.state == RefreshState.noData);

  @override
  List<Object?> get props => [status, reports, retention, revenue];
}

/// No Analytics export has landed yet, so no range can be reported.
final class DashboardNoDataFailure extends Failure {
  const DashboardNoDataFailure([super.message = 'No Analytics data yet']);
}
