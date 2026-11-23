import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';

void main() {
  final now = DateTime(2026, 11, 12, 15, 30);

  HistoryPoint point(DateTime date, double? e1rm, [String? id]) => HistoryPoint(
    date: date,
    workoutId: id ?? 'w${date.month}-${date.day}',
    bestE1rmKg: e1rm,
  );

  group('StrengthRange', () {
    test('starts at local midnight of the first day shown', () {
      expect(StrengthRange.weeks2.start(now), DateTime(2026, 10, 29));
      expect(StrengthRange.months6.start(now), DateTime(2026, 5, 12));
      expect(StrengthRange.year1.start(now), DateTime(2025, 11, 12));
      expect(StrengthRange.all.start(now), isNull);
    });

    test('a month end stays in the month of the start', () {
      expect(
        StrengthRange.months6.start(DateTime(2026, 8, 31, 9)),
        DateTime(2026, 2, 28),
      );
      expect(
        StrengthRange.months6.start(DateTime(2028, 8, 31)),
        DateTime(2028, 2, 29),
      );
      expect(
        StrengthRange.year1.start(DateTime(2028, 2, 29)),
        DateTime(2027, 2, 28),
      );
      expect(
        StrengthRange.months6.start(DateTime(2026, 3, 31)),
        DateTime(2025, 9, 30),
      );
    });
  });

  group('e1rmSeries', () {
    final history = [
      point(DateTime(2026, 1, 5), 90),
      point(DateTime(2026, 10, 28, 23, 59), 95),
      point(DateTime(2026, 10, 29), 100),
      point(DateTime(2026, 11, 1), null),
      point(DateTime(2026, 11, 12, 9), 110),
    ];

    test('the 2 weeks from midnight of their first day, with an e1RM', () {
      final series = e1rmSeries(
        history,
        range: StrengthRange.weeks2,
        now: now,
        unit: WeightUnit.kg,
      );
      expect(series, [
        (date: DateTime(2026, 10, 29), value: 100.0, workoutId: 'w10-29'),
        (date: DateTime(2026, 11, 12, 9), value: 110.0, workoutId: 'w11-12'),
      ]);
    });

    test('everything with an e1RM for all', () {
      final series = e1rmSeries(
        history,
        range: StrengthRange.all,
        now: now,
        unit: WeightUnit.kg,
      );
      expect([for (final p in series) p.value], [90, 95, 100, 110]);
    });

    test('values in whole pounds for a user who lifts in pounds', () {
      final series = e1rmSeries(
        [point(DateTime(2026, 11, 1), 100)],
        range: StrengthRange.weeks2,
        now: now,
        unit: WeightUnit.lb,
      );
      expect(series.single.value, 220);
    });

    test('empty without history', () {
      expect(
        e1rmSeries(
          const [],
          range: StrengthRange.all,
          now: now,
          unit: WeightUnit.kg,
        ),
        isEmpty,
      );
    });
  });

  group('sessionsFrom', () {
    final history = [
      point(DateTime(2026, 8, 19), 95),
      point(DateTime(2026, 10, 29), null),
      point(DateTime(2026, 11, 1), 100),
    ];

    test('the workouts from the start on, newest first', () {
      expect(
        [for (final p in sessionsFrom(history, DateTime(2026, 10, 29))) p.date],
        [DateTime(2026, 11, 1), DateTime(2026, 10, 29)],
      );
    });

    test('all of them without a start', () {
      expect(sessionsFrom(history, null).length, 3);
      expect(sessionsFrom(history, null).first.date, DateTime(2026, 11, 1));
    });
  });

  group('loggingTypeOf', () {
    StatRecord any() => StatRecord(value: 1, date: now, workoutId: 'w');

    test('timed with or without a weight', () {
      expect(
        loggingTypeOf(
          ExerciseStats(
            records: {
              RecordKind.longestDuration: any(),
              RecordKind.heaviestWeight: any(),
            },
          ),
        ),
        LoggingType.weightDuration,
      );
      expect(
        loggingTypeOf(
          ExerciseStats(records: {RecordKind.longestDuration: any()}),
        ),
        LoggingType.duration,
      );
    });

    test('a load, or reps alone', () {
      expect(
        loggingTypeOf(
          ExerciseStats(records: {RecordKind.heaviestWeight: any()}),
        ),
        LoggingType.weightReps,
      );
      expect(
        loggingTypeOf(ExerciseStats(records: {RecordKind.mostReps: any()})),
        LoggingType.reps,
      );
    });
  });

  group('orderedRecords', () {
    StatRecord record(double value) =>
        StatRecord(value: value, date: now, workoutId: 'w$value');

    test('in the listed order, whatever the stored order', () {
      final stats = ExerciseStats(
        records: {
          RecordKind.bestSetVolume: record(800),
          RecordKind.mostReps: record(12),
          RecordKind.bestE1rm: record(120),
          RecordKind.heaviestWeight: record(100),
        },
      );
      expect(
        [for (final entry in orderedRecords(stats)) entry.kind],
        [
          RecordKind.bestE1rm,
          RecordKind.heaviestWeight,
          RecordKind.mostReps,
          RecordKind.bestSetVolume,
        ],
      );
      expect(orderedRecords(stats).first.record, record(120));
    });

    test('only the kinds there are', () {
      final stats = ExerciseStats(
        records: {RecordKind.longestDuration: record(60)},
      );
      expect(orderedRecords(stats), [
        (kind: RecordKind.longestDuration, record: record(60)),
      ]);
      expect(orderedRecords(const ExerciseStats()), isEmpty);
    });
  });

  group('byLastTrained', () {
    ExerciseStats doneOn(List<DateTime> dates, {DateTime? last}) =>
        ExerciseStats(
          last: last == null
              ? null
              : LastSession(date: last, workoutId: 'last', sets: const []),
          history: [for (final date in dates) point(date, null)],
        );

    test('most recently trained first, ties by id', () {
      final trained = byLastTrained({
        'squat': doneOn([DateTime(2026, 10, 1)], last: DateTime(2026, 10, 1)),
        'bench': doneOn([DateTime(2026, 11, 1)], last: DateTime(2026, 11, 1)),
        'row': doneOn([DateTime(2026, 10, 1)], last: DateTime(2026, 10, 1)),
      });
      expect(
        [for (final t in trained) t.exerciseId],
        ['bench', 'row', 'squat'],
      );
      expect(trained.first.lastTrained, DateTime(2026, 11, 1));
    });

    test('the latest history point without a last session', () {
      final trained = byLastTrained({
        'squat': doneOn([DateTime(2026, 9, 1), DateTime(2026, 10, 1)]),
      });
      expect(trained.single.lastTrained, DateTime(2026, 10, 1));
    });

    test('stats without any workout are left out', () {
      expect(byLastTrained({'squat': const ExerciseStats()}), isEmpty);
    });
  });
}
