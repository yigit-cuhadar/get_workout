import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import '../../programs/domain/calendar_date.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../steps/domain/steps_usecases.dart';
import '../../volume/domain/volume_usecases.dart';
import '../domain/body_chart.dart';
import 'body_list_cubit.dart';

class BodyChartState extends Equatable {
  const BodyChartState({
    this.shown = const [BodySeries.weight],
    this.targetLine = true,
    this.stepsReadable = false,
    this.from,
    this.to,
    this.points = const {},
  });

  /// In the order picked.
  final List<BodySeries> shown;

  /// Whether the target weight shows as a line while weight is shown.
  final bool targetLine;

  /// Whether daily steps can be read here, so offered.
  final bool stepsReadable;

  /// The time the chart spans: from the range's first day to now, widened
  /// to whole weeks while bars show. Null while there are no entries.
  final DateTime? from;
  final DateTime? to;

  /// The values of each of [shown] within [from] and [to], oldest first;
  /// empty for bars not loaded (yet).
  final Map<BodySeries, List<SeriesPoint>> points;

  /// What can be picked.
  List<BodySeries> get available => [
    for (final series in BodySeries.values)
      if (series != BodySeries.dailySteps || stepsReadable) series,
  ];

  Map<BodySeries, ChartAxis> get axes => chartAxes(shown);

  @override
  List<Object?> get props => [
    shown,
    targetLine,
    stepsReadable,
    from,
    to,
    points,
  ];
}

/// The series of the Body chart: what the user picked (see [shownSeries]),
/// kept in their settings, over the range of the shared [BodyListCubit].
/// Lines come from the body entries; weekly sets follow the user's
/// workouts and daily steps are read from the health store, each only
/// while shown. Steps are offered only where the store can be read; this
/// never asks for access. Weeks start on ISO weekday [firstWeekday].
class BodyChartCubit extends Cubit<BodyChartState> {
  BodyChartCubit({
    required this.firstWeekday,
    required this._body,
    required this._settings,
    required WatchAuthUser watchAuthUser,
    required this._watchVolume,
    required GetStepsAccess getStepsAccess,
    required this._getDailySteps,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const BodyChartState()) {
    _bodySubscription = _body.stream.listen((_) => _publish());
    _settingsSubscription = _settings.stream.listen((_) => _publish());
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          _uid = uid;
          _publish();
        });
    unawaited(_checkSteps(getStepsAccess));
    _publish();
  }

  final int firstWeekday;
  final BodyListCubit _body;
  final SettingsCubit _settings;
  final WatchWeeklyVolume _watchVolume;
  final GetDailySteps _getDailySteps;
  final DateTime Function() _clock;
  late final StreamSubscription<BodyListState> _bodySubscription;
  late final StreamSubscription<SettingsState> _settingsSubscription;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<List<SeriesPoint>>? _setsSubscription;
  String? _uid;
  bool _stepsReadable = false;

  /// What [_sets] and [_steps] are for, so they are read again only when
  /// that changes. Steps are the device's, whoever is signed in.
  ({String uid, _Weeks weeks})? _setsKey;
  _Weeks? _stepsWeeks;
  List<SeriesPoint>? _sets;
  List<SeriesPoint>? _steps;

  /// Shows [series] too, or no longer; see [toggleSeries].
  Future<void> toggle(BodySeries series) =>
      _save(shown: toggleSeries(state.shown, series));

  Future<void> showTargetLine(bool show) => _save(targetLine: show);

  /// The change shows once the settings bring it back.
  Future<void> _save({List<BodySeries>? shown, bool? targetLine}) {
    final settings = _settings.state.settings;
    return _settings.update(
      settings.copyWith(
        bodyChart: BodyChartChoice(
          series: shown ?? state.shown,
          targetLine: targetLine ?? state.targetLine,
        ),
      ),
    );
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
    final choice = _settings.state.settings.bodyChart;
    final shown = shownSeries(
      choice,
      hasBodyFat: body.bodyFat.isNotEmpty,
      stepsReadable: _stepsReadable,
    );
    final start = chartStart(body.range, body.entries, now);
    final weeks = start == null ? null : chartWeeks(start, now, firstWeekday);
    _followSets(shown.contains(BodySeries.weeklySets) ? weeks : null);
    _readSteps(shown.contains(BodySeries.dailySteps) ? weeks : null, now);
    final bars = weeks != null && shown.any((series) => series.isBar);
    emit(
      BodyChartState(
        shown: shown,
        targetLine: choice?.targetLine ?? true,
        stepsReadable: _stepsReadable,
        from: bars ? weeks.first.toLocalDateTime() : start,
        to: bars
            ? weeks.last.addDays(DateTime.daysPerWeek).toLocalDateTime()
            : start == null
            ? null
            : now,
        points: {
          for (final series in shown)
            series: switch (series) {
              BodySeries.weeklySets => _sets ?? const [],
              BodySeries.dailySteps => _steps ?? const [],
              _ => linePoints(series, body.entries, body.bodyFat, start: start),
            },
        },
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
    if (key == null) return;
    _setsSubscription =
        _watchVolume((
          uid: key.uid,
          lastWeek: key.weeks.last,
          weeks: key.weeks.count,
          // Only the number of sets counts, not the muscles.
          muscles: const {},
        )).map(weeklySetTotals).listen(
          (sets) {
            _sets = sets;
            _publish();
          },
          // The repository logs it; the chart goes on without the bars.
          onError: (Object _) {},
        );
  }

  /// Reads the daily steps of [weeks] up to [now], once per weeks.
  void _readSteps(_Weeks? weeks, DateTime now) {
    if (!_stepsReadable || weeks == null || weeks == _stepsWeeks) return;
    _stepsWeeks = weeks;
    _steps = null;
    unawaited(() async {
      final days = <DailySteps>[];
      for (final span in stepSpans(weeks.first.toLocalDateTime(), now)) {
        switch (await _getDailySteps(span)) {
          case Ok(:final value):
            days.addAll(value);
          case Err(:final failure):
            Log.e('body', 'steps not read: ${failure.message}');
            return;
        }
      }
      if (isClosed || weeks != _stepsWeeks) return;
      _steps = weeklyStepAverages(days, firstWeekday);
      _publish();
    }());
  }

  @override
  Future<void> close() async {
    await _bodySubscription.cancel();
    await _settingsSubscription.cancel();
    await _userSubscription.cancel();
    await _setsSubscription?.cancel();
    return super.close();
  }
}

typedef _Weeks = ({CalendarDate first, CalendarDate last, int count});
