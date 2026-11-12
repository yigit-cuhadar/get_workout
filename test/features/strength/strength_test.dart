import 'package:flutter_test/flutter_test.dart';
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
      expect(StrengthRange.weeks12.start(now), DateTime(2026, 8, 20));
      expect(StrengthRange.months6.start(now), DateTime(2026, 5, 12));
      expect(StrengthRange.year1.start(now), DateTime(2025, 11, 12));
      expect(StrengthRange.all.start(now), isNull);
    });

    test('only the 12 weeks are free', () {
      expect(StrengthRange.free, StrengthRange.weeks12);
      expect(
        [for (final range in StrengthRange.values) range.premium],
        [false, true, true, true],
      );
    });

    test('a Premium range falls back to the free one unless known Premium', () {
      expect(StrengthRange.year1.allowed(true), StrengthRange.year1);
      expect(StrengthRange.year1.allowed(false), StrengthRange.free);
      expect(StrengthRange.all.allowed(null), StrengthRange.free);
      expect(StrengthRange.weeks12.allowed(false), StrengthRange.weeks12);
    });
  });

  group('e1rmSeries', () {
    final history = [
      point(DateTime(2026, 1, 5), 90),
      point(DateTime(2026, 8, 19, 23, 59), 95),
      point(DateTime(2026, 8, 20), 100),
      point(DateTime(2026, 9, 1), null),
      point(DateTime(2026, 11, 12, 9), 110),
    ];

    test('the 12 weeks from midnight of their first day, with an e1RM', () {
      final series = e1rmSeries(
        history,
        range: StrengthRange.weeks12,
        now: now,
        unit: WeightUnit.kg,
      );
      expect(series, [
        (date: DateTime(2026, 8, 20), value: 100.0, workoutId: 'w8-20'),
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

    test('values in pounds for a user who lifts in pounds', () {
      final series = e1rmSeries(
        [point(DateTime(2026, 11, 1), 100)],
        range: StrengthRange.weeks12,
        now: now,
        unit: WeightUnit.lb,
      );
      expect(series.single.value, closeTo(220.46, 0.01));
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

  group('hasE1rmBefore', () {
    test('an e1RM before the range starts', () {
      expect(
        hasE1rmBefore(
          [point(DateTime(2026, 8, 19, 23, 59), 95)],
          range: StrengthRange.weeks12,
          now: now,
        ),
        isTrue,
      );
    });

    test('not for results inside the range or without an e1RM', () {
      expect(
        hasE1rmBefore(
          [point(DateTime(2026, 1, 1), null), point(DateTime(2026, 8, 20), 99)],
          range: StrengthRange.weeks12,
          now: now,
        ),
        isFalse,
      );
    });

    test('never before all', () {
      expect(
        hasE1rmBefore(
          [point(DateTime(2000, 1, 1), 50)],
          range: StrengthRange.all,
          now: now,
        ),
        isFalse,
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
          RecordKind.heaviestWeight,
          RecordKind.bestE1rm,
          RecordKind.mostReps,
          RecordKind.bestSetVolume,
        ],
      );
      expect(orderedRecords(stats)[1].record, record(120));
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
