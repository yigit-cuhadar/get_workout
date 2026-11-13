import 'package:flutter_test/flutter_test.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/body/domain/body_chart.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';

void main() {
  group('series', () {
    test('the measurements are every one recorded, pairs as Compare', () {
      expect([
        for (final series in BodySeries.values)
          if (series.measurements.isNotEmpty) series.measurements,
      ], pairedMeasurements(BodyMeasurement.values.toSet()));
    });

    test('codes read back; unknown ones are null', () {
      for (final series in BodySeries.values) {
        expect(BodySeries.fromCode(series.code), series);
      }
      expect(BodySeries.fromCode('wingspan'), isNull);
    });
  });

  group('shown series', () {
    bool all(BodySeries _) => true;
    bool noSteps(BodySeries series) => series != BodySeries.dailySteps;

    test('default to weight, with body fat once there is some', () {
      expect(shownSeries(null, hasBodyFat: false, visible: all), [
        BodySeries.weight,
      ]);
      expect(shownSeries(null, hasBodyFat: true, visible: all), [
        BodySeries.weight,
        BodySeries.bodyFat,
      ]);
    });

    test('follow the choice, leaving out what does not show now', () {
      const choice = BodyChartChoice(
        series: [BodySeries.dailySteps, BodySeries.thigh],
      );
      expect(shownSeries(choice, hasBodyFat: true, visible: all), [
        BodySeries.dailySteps,
        BodySeries.thigh,
      ]);
      expect(shownSeries(choice, hasBodyFat: true, visible: noSteps), [
        BodySeries.thigh,
      ]);
    });

    test('are at most three, each once; none left gives the default', () {
      const many = BodyChartChoice(
        series: [
          BodySeries.waist,
          BodySeries.waist,
          BodySeries.hips,
          BodySeries.chest,
          BodySeries.neck,
        ],
      );
      expect(shownSeries(many, hasBodyFat: false, visible: all), [
        BodySeries.waist,
        BodySeries.hips,
        BodySeries.chest,
      ]);
      expect(
        shownSeries(
          const BodyChartChoice(series: [BodySeries.dailySteps]),
          hasBodyFat: false,
          visible: noSteps,
        ),
        [BodySeries.weight],
      );
    });

    test('toggle adds at the end and removes, never past three or to none', () {
      const shown = [BodySeries.weight, BodySeries.bodyFat];
      expect(toggleSeries(shown, BodySeries.weeklySets, visible: all), [
        BodySeries.weight,
        BodySeries.bodyFat,
        BodySeries.weeklySets,
      ]);
      expect(toggleSeries(shown, BodySeries.weight, visible: all), [
        BodySeries.bodyFat,
      ]);
      const full = [BodySeries.weight, BodySeries.bodyFat, BodySeries.waist];
      expect(toggleSeries(full, BodySeries.hips, visible: all), full);
      expect(
        toggleSeries([BodySeries.weight], BodySeries.weight, visible: all),
        [BodySeries.weight],
      );
    });

    test('toggle keeps chosen series that do not show now', () {
      const chosen = [
        BodySeries.dailySteps,
        BodySeries.weight,
        BodySeries.waist,
      ];
      expect(toggleSeries(chosen, BodySeries.thigh, visible: noSteps), [
        ...chosen,
        BodySeries.thigh,
      ]);
      expect(
        toggleSeries(chosen, BodySeries.dailySteps, visible: noSteps),
        chosen,
      );
      expect(
        toggleSeries(
          [BodySeries.dailySteps, BodySeries.weight],
          BodySeries.weight,
          visible: noSteps,
        ),
        [BodySeries.dailySteps, BodySeries.weight],
      );
    });
  });

  group('axes', () {
    test('the first line left, the second right, a third none', () {
      expect(
        chartAxes([BodySeries.weight, BodySeries.bodyFat, BodySeries.waist]),
        {
          BodySeries.weight: ChartAxis.left,
          BodySeries.bodyFat: ChartAxis.right,
          BodySeries.waist: ChartAxis.none,
        },
      );
    });

    test('bars take an axis only once the lines have theirs', () {
      expect(chartAxes([BodySeries.weeklySets, BodySeries.weight]), {
        BodySeries.weeklySets: ChartAxis.right,
        BodySeries.weight: ChartAxis.left,
      });
      expect(
        chartAxes([
          BodySeries.weeklySets,
          BodySeries.weight,
          BodySeries.bodyFat,
        ]),
        {
          BodySeries.weeklySets: ChartAxis.none,
          BodySeries.weight: ChartAxis.left,
          BodySeries.bodyFat: ChartAxis.right,
        },
      );
      expect(chartAxes([BodySeries.dailySteps, BodySeries.weeklySets]), {
        BodySeries.dailySteps: ChartAxis.left,
        BodySeries.weeklySets: ChartAxis.right,
      });
    });
  });

  group('line points', () {
    final measured = BodyEntry(
      id: 'm',
      date: DateTime(2026, 11, 1),
      weightKg: 80,
      measurements: const {
        BodyMeasurement.waist: 85,
        BodyMeasurement.leftThigh: 58,
        BodyMeasurement.rightThigh: 59,
        BodyMeasurement.leftCalf: 38,
      },
    );
    final logged = BodyEntry(
      id: 'w',
      date: DateTime(2026, 10, 1),
      weightKg: 82,
    );
    final old = BodyEntry(id: 'o', date: DateTime(2026, 1, 1), weightKg: 90);
    final entries = [measured, logged, old];
    const bodyFat = {'m': 20.0};

    List<SeriesPoint> points(BodySeries series, {DateTime? start}) =>
        linePoints(series, entries, bodyFat, start: start);

    test('weights from the start on, oldest first', () {
      expect(points(BodySeries.weight, start: DateTime(2026, 9, 1)), [
        SeriesPoint(logged.date, 82),
        SeriesPoint(measured.date, 80),
      ]);
      expect(points(BodySeries.weight), hasLength(3));
    });

    test('body fat splits the weight into fat and lean mass', () {
      expect(points(BodySeries.bodyFat), [SeriesPoint(measured.date, 20)]);
      expect(points(BodySeries.fatMass), [SeriesPoint(measured.date, 16)]);
      expect(points(BodySeries.leanMass), [SeriesPoint(measured.date, 64)]);
    });

    test('a pair plots the mean of the sides measured, keeping both', () {
      expect(points(BodySeries.waist), [SeriesPoint(measured.date, 85)]);
      expect(points(BodySeries.thigh), [
        SeriesPoint(measured.date, 58.5, const [58, 59]),
      ]);
      expect(points(BodySeries.calf), [
        SeriesPoint(measured.date, 38, const [38, null]),
      ]);
      expect(points(BodySeries.neck), isEmpty);
    });
  });

  group('time', () {
    final now = DateTime(2026, 11, 12, 9);

    test('all starts on the day of the oldest value shown', () {
      expect(
        chartStart(StrengthRange.all, now, [
          DateTime(2026, 5, 2, 18),
          DateTime(2025, 3, 4, 7),
        ]),
        DateTime(2025, 3, 4),
      );
      expect(chartStart(StrengthRange.all, now, const []), isNull);
      expect(
        chartStart(StrengthRange.weeks12, now, [DateTime(2020)]),
        StrengthRange.weeks12.start(now),
      );
    });

    test('weeks run from the one of the start to the current one', () {
      final weeks = chartWeeks(DateTime(2026, 10, 28), now, DateTime.monday);
      expect(weeks.first, CalendarDate(2026, 10, 26));
      expect(weeks.last, CalendarDate(2026, 11, 9));
      expect(weeks.count, 3);
    });
  });

  test('steps are read in spans the health store allows', () {
    final first = DateTime(2025, 1, 6);
    final last = DateTime(2026, 2, 3, 9);
    final spans = stepSpans(first, last);
    expect(spans.map((span) => span.first), [
      first,
      DateTime(2025, 1, 6 + maxStepDays),
    ]);
    expect(spans.first.last, DateTime(2025, 1, 5 + maxStepDays));
    expect(spans.last.last, last);
    expect(stepSpans(DateTime(2026, 2, 2), last), [
      (first: DateTime(2026, 2, 2), last: last),
    ]);
  });

  test('weekly sets total every working set of the week', () {
    VolumeEntry entry(int sets) => VolumeEntry(
      workoutId: 'w',
      workoutName: 'W',
      startedAt: DateTime(2026, 11, 3),
      exerciseId: 'e',
      exerciseName: 'E',
      sets: sets,
      muscles: (main: const [], secondary: const []),
    );
    expect(
      weeklySetTotals([
        WeekVolume(CalendarDate(2026, 10, 26), const []),
        WeekVolume(CalendarDate(2026, 11, 2), [entry(3), entry(4)]),
      ]),
      [
        SeriesPoint(DateTime(2026, 10, 26), 0),
        SeriesPoint(DateTime(2026, 11, 2), 7),
      ],
    );
  });

  test('daily steps average per week over the days done', () {
    final days = [
      DailySteps(DateTime(2026, 11, 1), 4000), // a Sunday
      DailySteps(DateTime(2026, 11, 2), 6000),
      DailySteps(DateTime(2026, 11, 3), 9000),
      DailySteps(DateTime(2026, 11, 4), 500), // today, under way
    ];
    final now = DateTime(2026, 11, 4, 8);
    expect(weeklyStepAverages(days, DateTime.monday, now: now), [
      SeriesPoint(DateTime(2026, 10, 26), 4000),
      SeriesPoint(DateTime(2026, 11, 2), 7500),
    ]);
    // Today alone counts as it is.
    expect(
      weeklyStepAverages(
        [DailySteps(DateTime(2026, 11, 2), 700)],
        DateTime.monday,
        now: DateTime(2026, 11, 2, 9),
      ),
      [SeriesPoint(DateTime(2026, 11, 2), 700)],
    );
  });

  test('a tapped position finds each series\' value, to the microsecond', () {
    // Firestore keeps microseconds; the chart places points in ms.
    final logged = DateTime(2026, 11, 3, 7, 30, 0, 123, 456);
    final points = {
      BodySeries.weight: [SeriesPoint(logged, 80)],
      BodySeries.waist: [SeriesPoint(DateTime(2026, 11, 1), 84)],
      BodySeries.weeklySets: [SeriesPoint(DateTime(2026, 11, 2), 12)],
    };
    final shown = points.keys.toList();
    final at = logged.millisecondsSinceEpoch.toDouble().round();

    expect(pointsAt(shown, points, at), [
      (BodySeries.weight, SeriesPoint(logged, 80)),
      (BodySeries.weeklySets, SeriesPoint(DateTime(2026, 11, 2), 12)),
    ]);
  });
}
