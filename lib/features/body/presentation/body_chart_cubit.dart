import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program_usecases.dart';
import '../../steps/domain/steps_usecases.dart';
import '../../strength/domain/strength.dart';
import '../../volume/domain/volume_usecases.dart';
import '../domain/body_chart.dart';
import '../domain/body_usecases.dart';
import 'body_list_cubit.dart';

class BodyChartState extends Equatable {
  const BodyChartState({
    this.shown = const [BodySeries.weight],
    this.targetLine = true,
    this.stepsReadable = false,
    this.premium,
    this.from,
    this.to,
    this.points = const {},
    this.loading = const {},
    this.failed = const {},
    this.saveFailed = false,
  });

  /// In the order picked.
  final List<BodySeries> shown;

  /// Whether the target weight shows as a line while weight is shown.
  final bool targetLine;

  /// Whether daily steps can be read here, so offered.
  final bool stepsReadable;

  /// Whether the user has Premium, which the training series need; null
  /// while not known, when they are neither locked nor read.
  final bool? premium;

  /// The time the chart spans: from its first day (see [chartStart]) to
  /// now, widened to whole weeks while bars show. Null while there is
  /// nothing to show.
  final DateTime? from;
  final DateTime? to;

  /// The values of each of [shown] within [from] and [to], oldest first;
  /// empty for bars not read.
  final Map<BodySeries, List<SeriesPoint>> points;

  /// Bars of [shown] being read, and those that could not be.
  final Set<BodySeries> loading;
  final Set<BodySeries> failed;

  /// The choice could not be kept; tell the user, then call
  /// [BodyChartCubit.saveFailureShown].
  final bool saveFailed;

  /// What can be picked.
  List<BodySeries> get available => [
    for (final series in BodySeries.values)
      if (series != BodySeries.dailySteps || stepsReadable) series,
  ];

  /// Whether picking [series] needs Premium first: only once the user is
  /// known not to have it.
  bool locked(BodySeries series) => series.isBar && premium == false;

  Map<BodySeries, ChartAxis> get axes => chartAxes(shown);

  @override
  List<Object?> get props => [
    shown,
    targetLine,
    stepsReadable,
    premium,
    from,
    to,
    points,
    loading,
    failed,
    saveFailed,
  ];
}

/// The series of the Body chart: what the user picked (see [shownSeries]),
/// kept on this device, over the range of the shared [BodyListCubit].
/// Lines come from the body entries; with Premium, weekly sets follow the
/// user's workouts and daily steps are read from the health store, each
/// only while shown. Steps are offered only where the store can be read;
/// this never asks for access. Weeks start on ISO weekday [firstWeekday].
class BodyChartCubit extends Cubit<BodyChartState> {
  BodyChartCubit({
    required this.firstWeekday,
    required this._body,
    required WatchAuthUser watchAuthUser,
    required WatchPremium watchPremium,
    required this._loadChoice,
    required this._saveChoice,
    required this._watchVolume,
    required GetStepsAccess getStepsAccess,
    required this._getDailySteps,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const BodyChartState()) {
    _bodySubscription = _body.stream.listen((_) => _publish());
    _premiumSubscription = watchPremium().listen((premium) {
      _premium = premium;
      _publish();
    });
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
    unawaited(_checkSteps(getStepsAccess));
    _publish();
  }

  final int firstWeekday;
  final BodyListCubit _body;
  final LoadBodyChart _loadChoice;
  final SaveBodyChart _saveChoice;
  final WatchWeeklyVolume _watchVolume;
  final GetDailySteps _getDailySteps;
  final DateTime Function() _clock;
  late final StreamSubscription<BodyListState> _bodySubscription;
  late final StreamSubscription<bool?> _premiumSubscription;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<List<SeriesPoint>>? _setsSubscription;
  String? _uid;
  bool? _premium;
  bool _stepsReadable = false;

  /// The user's choice as last made, kept even before it is stored; null
  /// until they choose. Nothing is chosen before [_loaded].
  BodyChartChoice? _choice;
  bool _loaded = false;
  bool _saveFailed = false;

  /// What [_sets] and [_steps] were read for, so they are read again only
  /// when that changes. Steps are the device's, whoever is signed in.
  ({String uid, _Weeks weeks})? _setsKey;
  _Weeks? _stepsWeeks;

  /// Counts the step reads started; only the latest one applies.
  int _stepsRead = 0;

  /// Read the steps again even for the same weeks.
  bool _rereadSteps = false;
  List<SeriesPoint>? _sets;
  List<SeriesPoint>? _steps;
  bool _setsFailed = false;
  bool _stepsFailed = false;

  /// Shows [series] too, or no longer; see [toggleSeries].
  Future<void> toggle(BodySeries series) async {
    if (!_loaded) return;
    final chosen = _chosen();
    final next = toggleSeries(chosen, series, visible: _visible);
    if (identical(next, chosen)) return;
    await _choose(
      BodyChartChoice(series: next, targetLine: _choice?.targetLine ?? true),
    );
  }

  /// Shows [series] too, never taking it away: e.g. once Premium unlocked
  /// it, which the stored choice may already hold.
  Future<void> add(BodySeries series) async {
    if (!_loaded || _chosen().contains(series)) return;
    await toggle(series);
  }

  Future<void> showTargetLine(bool show) async {
    if (!_loaded) return;
    await _choose(BodyChartChoice(series: _chosen(), targetLine: show));
  }

  /// The choice as last made, hidden series included. While none of it
  /// shows, the chart shows the default, which a change then builds on.
  List<BodySeries> _chosen() {
    final stored = _choice?.series ?? const <BodySeries>[];
    if (stored.any(_visible)) return stored;
    return [...stored, ..._defaultSeries()];
  }

  /// Reads [series] again after it failed.
  void retry(BodySeries series) {
    switch (series) {
      case BodySeries.weeklySets:
        _setsKey = null;
      case BodySeries.dailySteps:
        _rereadSteps = true;
      default:
        return;
    }
    _publish();
  }

  /// Reads the steps again, e.g. as the app comes back with today's grown.
  void refreshSteps() {
    _rereadSteps = true;
    _publish();
  }

  void saveFailureShown() {
    _saveFailed = false;
    _publish();
  }

  bool _visible(BodySeries series) =>
      (series != BodySeries.dailySteps || _stepsReadable) &&
      (!series.isBar || _premium == true);

  List<BodySeries> _defaultSeries() => shownSeries(
    null,
    hasBodyFat: _body.state.bodyFat.isNotEmpty,
    visible: _visible,
  );

  Future<void> _choose(BodyChartChoice choice) async {
    final uid = _uid;
    if (uid == null) return;
    _choice = choice;
    _publish();
    final saved = await _saveChoice((uid: uid, choice: choice));
    if (saved.failureOrNull case final failure? when !isClosed) {
      Log.e('body', 'chart choice not kept: ${failure.message}');
      _saveFailed = true;
      _publish();
    }
  }

  Future<void> _onUser(String? uid) async {
    _uid = uid;
    _choice = null;
    _loaded = false;
    _publish();
    if (uid == null) return;
    final loaded = await _loadChoice(uid);
    if (isClosed || uid != _uid) return;
    if (loaded.failureOrNull case final failure?) {
      Log.e('body', 'chart choice not read: ${failure.message}');
    }
    _choice = loaded.valueOrNull;
    _loaded = true;
    _publish();
  }

  Future<void> _checkSteps(GetStepsAccess getAccess) async {
    final access = await getAccess();
    if (isClosed) return;
    _stepsReadable = access.valueOrNull?.readable ?? false;
    _publish();
  }

  void _publish() {
    if (isClosed) return;
    final body = _body.state;
    final now = _clock();
    final shown = shownSeries(
      _choice,
      hasBodyFat: body.bodyFat.isNotEmpty,
      visible: _visible,
    );
    final all = body.range == StrengthRange.all;
    final rangeStart = body.range.start(now);
    // "All" reads the workouts from the earliest date, the steps from the
    // oldest entry or a year back, then starts at the oldest value.
    final yearBack = DateTime(now.year - 1, now.month, now.day);
    final oldestEntry = body.entries.lastOrNull?.date;
    _followSets(
      shown.contains(BodySeries.weeklySets)
          ? chartWeeks(rangeStart ?? earliestDate, now, firstWeekday)
          : null,
    );
    _readSteps(
      shown.contains(BodySeries.dailySteps)
          ? chartWeeks(
              rangeStart ??
                  (oldestEntry != null && oldestEntry.isBefore(yearBack)
                      ? oldestEntry
                      : yearBack),
              now,
              firstWeekday,
            )
          : null,
      now,
    );
    List<SeriesPoint> bars(BodySeries series) => switch (series) {
      BodySeries.weeklySets => _sets ?? const [],
      _ => _steps ?? const [],
    };
    final lines = {
      for (final series in shown)
        if (!series.isBar)
          series: linePoints(
            series,
            body.entries,
            body.bodyFat,
            start: rangeStart,
          ),
    };
    final start = chartStart(body.range, now, [
      if (all)
        for (final series in shown)
          if (series.isBar)
            ?bars(series).where((point) => point.value > 0).firstOrNull?.date
          else
            ?lines[series]!.firstOrNull?.date,
    ]);
    final weeks = start == null ? null : chartWeeks(start, now, firstWeekday);
    final hasBars = weeks != null && shown.any((series) => series.isBar);
    final from = hasBars ? weeks.first.toLocalDateTime() : start;
    emit(
      BodyChartState(
        shown: shown,
        targetLine: _choice?.targetLine ?? true,
        stepsReadable: _stepsReadable,
        premium: _premium,
        from: from,
        to: start == null
            ? null
            : hasBars
            ? weeks.last.addDays(DateTime.daysPerWeek).toLocalDateTime()
            : now,
        points: {
          for (final series in shown)
            series: series.isBar
                ? [
                    if (from != null)
                      for (final point in bars(series))
                        if (!point.date.isBefore(from)) point,
                  ]
                : lines[series]!,
        },
        loading: {
          if (shown.contains(BodySeries.weeklySets) &&
              _sets == null &&
              !_setsFailed)
            BodySeries.weeklySets,
          if (shown.contains(BodySeries.dailySteps) &&
              _steps == null &&
              !_stepsFailed)
            BodySeries.dailySteps,
        },
        failed: {
          if (shown.contains(BodySeries.weeklySets) && _setsFailed)
            BodySeries.weeklySets,
          if (shown.contains(BodySeries.dailySteps) && _stepsFailed)
            BodySeries.dailySteps,
        },
        saveFailed: _saveFailed,
      ),
    );
  }

  /// Follows the weekly sets of [weeks]; none without.
  void _followSets(_Weeks? weeks) {
    final uid = _uid;
    final key = uid == null || weeks == null ? null : (uid: uid, weeks: weeks);
    if (key == _setsKey) return;
    unawaited(_setsSubscription?.cancel());
    _setsSubscription = null;
    _setsKey = key;
    _sets = null;
    _setsFailed = false;
    if (key == null) return;
    _setsSubscription =
        _watchVolume((
              uid: key.uid,
              lastWeek: key.weeks.last,
              weeks: key.weeks.count,
              // Only the number of sets counts, not the muscles.
              muscles: const {},
            ))
            .map(weeklySetTotals)
            .listen(
              (sets) {
                _sets = sets;
                _setsFailed = false;
                _publish();
              },
              // The repository logs it.
              onError: (Object _) {
                _sets = null;
                _setsFailed = true;
                _publish();
              },
            );
  }

  /// Reads the daily steps of [wanted] up to [now], once per weeks unless
  /// asked again; only the latest read applies, an older one stops between
  /// its spans. Other weeks drop the steps read for the last ones.
  void _readSteps(_Weeks? wanted, DateTime now) {
    final weeks = _stepsReadable ? wanted : null;
    if (weeks == _stepsWeeks && !_rereadSteps) return;
    if (weeks != _stepsWeeks) _steps = null;
    _stepsWeeks = weeks;
    _rereadSteps = false;
    _stepsFailed = false;
    final read = ++_stepsRead;
    if (weeks == null) return;
    unawaited(() async {
      final days = <DailySteps>[];
      for (final span in stepSpans(weeks.first.toLocalDateTime(), now)) {
        final result = await _getDailySteps(span);
        if (isClosed || read != _stepsRead) return;
        switch (result) {
          case Ok(:final value):
            days.addAll(value);
          case Err(:final failure):
            Log.e('body', 'steps not read: ${failure.message}');
            _stepsFailed = true;
            _publish();
            return;
        }
      }
      _steps = weeklyStepAverages(days, firstWeekday, now: now);
      _publish();
    }());
  }

  @override
  Future<void> close() async {
    await _bodySubscription.cancel();
    await _premiumSubscription.cancel();
    await _userSubscription.cancel();
    await _setsSubscription?.cancel();
    return super.close();
  }
}

typedef _Weeks = ({CalendarDate first, CalendarDate last, int count});
