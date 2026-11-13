import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import '../../programs/domain/calendar_date.dart';
import '../../strength/domain/strength.dart';
import '../../volume/domain/weekly_volume.dart';
import 'body_entry.dart';

/// Where a series is listed when picking what the chart shows.
enum BodySeriesGroup { body, measurements, training }

/// What the Body chart can show. [code] is its key in
/// `settings.bodyChart.series`.
enum BodySeries {
  weight('weight', BodySeriesGroup.body),
  bodyFat('bodyFat', BodySeriesGroup.body),
  fatMass('fatMass', BodySeriesGroup.body),
  leanMass('leanMass', BodySeriesGroup.body),
  neck('neck', BodySeriesGroup.measurements, [BodyMeasurement.neck]),
  shoulders('shoulders', BodySeriesGroup.measurements, [
    BodyMeasurement.shoulders,
  ]),
  chest('chest', BodySeriesGroup.measurements, [BodyMeasurement.chest]),
  waist('waist', BodySeriesGroup.measurements, [BodyMeasurement.waist]),
  abdomen('abdomen', BodySeriesGroup.measurements, [BodyMeasurement.abdomen]),
  hips('hips', BodySeriesGroup.measurements, [BodyMeasurement.hips]),
  upperArm('upperArm', BodySeriesGroup.measurements, [
    BodyMeasurement.leftUpperArm,
    BodyMeasurement.rightUpperArm,
  ]),
  forearm('forearm', BodySeriesGroup.measurements, [
    BodyMeasurement.leftForearm,
    BodyMeasurement.rightForearm,
  ]),
  thigh('thigh', BodySeriesGroup.measurements, [
    BodyMeasurement.leftThigh,
    BodyMeasurement.rightThigh,
  ]),
  calf('calf', BodySeriesGroup.measurements, [
    BodyMeasurement.leftCalf,
    BodyMeasurement.rightCalf,
  ]),

  /// Working sets per week.
  weeklySets('weeklySets', BodySeriesGroup.training),

  /// Steps a day, averaged per week.
  dailySteps('dailySteps', BodySeriesGroup.training);

  const BodySeries(this.code, this.group, [this.measurements = const []]);

  final String code;
  final BodySeriesGroup group;

  /// The tape measurements shown: one, or both sides of a pair, left first.
  final List<BodyMeasurement> measurements;

  /// The most series the chart shows at once.
  static const maxShown = 3;

  /// One bar per week rather than a line through the entries.
  bool get isBar => group == BodySeriesGroup.training;

  /// Null for unknown codes, e.g. from a newer app version.
  static BodySeries? fromCode(Object? code) {
    for (final series in values) {
      if (series.code == code) return series;
    }
    return null;
  }
}

/// What the user picked for the Body chart (`settings.bodyChart`).
class BodyChartChoice extends Equatable {
  const BodyChartChoice({required this.series, this.targetLine = true});

  /// In the order picked.
  final List<BodySeries> series;

  /// Whether the target weight shows as a line while weight is shown.
  final bool targetLine;

  @override
  List<Object?> get props => [series, targetLine];
}

/// What the chart shows under [choice], null until the user picks: weight,
/// with body fat once [hasBodyFat]. Daily steps only where they are
/// [stepsReadable]; at most [BodySeries.maxShown]; a choice left with none
/// gives the default.
List<BodySeries> shownSeries(
  BodyChartChoice? choice, {
  required bool hasBodyFat,
  required bool stepsReadable,
}) {
  final shown = {
    for (final series in choice?.series ?? const <BodySeries>[])
      if (series != BodySeries.dailySteps || stepsReadable) series,
  }.take(BodySeries.maxShown).toList();
  if (shown.isNotEmpty) return shown;
  return [BodySeries.weight, if (hasBodyFat) BodySeries.bodyFat];
}

/// [shown] with [series] taken away, or added at the end; unchanged when
/// that would leave none or more than [BodySeries.maxShown].
List<BodySeries> toggleSeries(List<BodySeries> shown, BodySeries series) {
  if (shown.contains(series)) {
    return shown.length == 1
        ? shown
        : [
            for (final other in shown)
              if (other != series) other,
          ];
  }
  return shown.length >= BodySeries.maxShown ? shown : [...shown, series];
}

/// Which value axis a series is read on.
enum ChartAxis { left, right, none }

/// The axis of each of [shown]: the first line on the left, the second on
/// the right; bars take an axis still free after the lines, in order. The
/// rest have none: their values show when a point is tapped.
Map<BodySeries, ChartAxis> chartAxes(List<BodySeries> shown) {
  final free = [ChartAxis.left, ChartAxis.right];
  final axes = <BodySeries, ChartAxis>{};
  for (final series in [
    ...shown.where((series) => !series.isBar),
    ...shown.where((series) => series.isBar),
  ]) {
    axes[series] = free.isEmpty ? ChartAxis.none : free.removeAt(0);
  }
  return {for (final series in shown) series: axes[series]!};
}

/// One value of a series: an entry's, or a week's from its first day.
class SeriesPoint extends Equatable {
  const SeriesPoint(this.date, this.value, [this.sides = const []]);

  final DateTime date;

  /// Metric (kg, cm, %), or sets or steps. For a pair of measurements, the
  /// mean of the sides measured.
  final double value;

  /// For a pair of measurements, the left and the right side, null where
  /// not measured; empty otherwise.
  final List<double?> sides;

  @override
  List<Object?> get props => [date, value, sides];
}

/// The first day the chart shows: [range]'s start, or for
/// [StrengthRange.all] the day of the oldest of [entries] (newest first);
/// null then without entries.
DateTime? chartStart(
  StrengthRange range,
  List<BodyEntry> entries,
  DateTime now,
) {
  if (range.start(now) case final start?) return start;
  final oldest = entries.lastOrNull?.date;
  return oldest == null
      ? null
      : CalendarDate.of(oldest.toLocal()).toLocalDateTime();
}

/// The values of line [series] (not [BodySeries.isBar]) of [entries]
/// (newest first) from [start] on (null: all), oldest first. [bodyFat] is
/// the body fat by entry id; fat and lean mass split an entry's weight by
/// it, so they, body fat and measurements exist only on measurement days.
List<SeriesPoint> linePoints(
  BodySeries series,
  List<BodyEntry> entries,
  Map<String, double> bodyFat, {
  required DateTime? start,
}) {
  SeriesPoint? pointOf(BodyEntry entry) {
    final kg = entry.weightKg;
    final percent = bodyFat[entry.id];
    final fatKg = kg == null || percent == null ? null : kg * percent / 100;
    final value = switch (series) {
      BodySeries.weight => kg,
      BodySeries.bodyFat => percent,
      BodySeries.fatMass => fatKg,
      BodySeries.leanMass => fatKg == null ? null : kg! - fatKg,
      // Measurements below; bars have no value per entry.
      _ => null,
    };
    if (value != null) return SeriesPoint(entry.date, value);
    if (series.measurements.isEmpty) return null;
    final sides = [
      for (final measurement in series.measurements)
        entry.measurements[measurement],
    ];
    final measured = sides.nonNulls.toList();
    if (measured.isEmpty) return null;
    final mean = measured.reduce((a, b) => a + b) / measured.length;
    return SeriesPoint(entry.date, mean, sides.length > 1 ? sides : const []);
  }

  return [
    for (final entry in entries.reversed)
      if (start == null || !entry.date.isBefore(start)) ?pointOf(entry),
  ];
}

/// The weeks the chart's bars cover: from the one [start] falls in to the
/// one [now] falls in, weeks starting on ISO weekday [firstWeekday].
({CalendarDate first, CalendarDate last, int count}) chartWeeks(
  DateTime start,
  DateTime now,
  int firstWeekday,
) {
  final first = CalendarDate.of(start.toLocal()).startOfWeek(firstWeekday);
  final last = CalendarDate.of(now.toLocal()).startOfWeek(firstWeekday);
  final days = last.toLocalDateTime().difference(first.toLocalDateTime());
  // Rounded: a daylight saving change makes a week an hour short or long.
  final count = (days.inHours / (24 * DateTime.daysPerWeek)).round() + 1;
  return (first: first, last: last, count: count);
}

/// The days from [first] (a local midnight) to [last] in spans the health
/// store reads in one go: at most [maxStepDays] days each, oldest first.
List<({DateTime first, DateTime last})> stepSpans(
  DateTime first,
  DateTime last,
) => [
  for (
    var start = first;
    !start.isAfter(last);
    start = DateTime(start.year, start.month, start.day + maxStepDays)
  )
    (
      first: start,
      last: switch (DateTime(
        start.year,
        start.month,
        start.day + maxStepDays - 1,
      )) {
        final end when end.isBefore(last) => end,
        _ => last,
      },
    ),
];

/// The working sets of each of [weeks], oldest first.
List<SeriesPoint> weeklySetTotals(List<WeekVolume> weeks) => [
  for (final week in weeks)
    SeriesPoint(
      week.start.toLocalDateTime(),
      week.entries.fold(0, (total, entry) => total + entry.sets).toDouble(),
    ),
];

/// The average steps a day of each week of [days] (oldest first), weeks
/// starting on ISO weekday [firstWeekday]; a week averages the days the
/// health store gave, so the current one counts up to today.
List<SeriesPoint> weeklyStepAverages(List<DailySteps> days, int firstWeekday) {
  final byWeek = <CalendarDate, List<int>>{};
  for (final day in days) {
    final week = CalendarDate.of(day.day).startOfWeek(firstWeekday);
    (byWeek[week] ??= []).add(day.count);
  }
  return [
    for (final MapEntry(key: week, value: counts) in byWeek.entries)
      SeriesPoint(
        week.toLocalDateTime(),
        counts.reduce((a, b) => a + b) / counts.length,
      ),
  ];
}
