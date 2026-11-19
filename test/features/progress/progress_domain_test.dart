import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/progress/domain/body_snapshot.dart';
import 'package:get_workout/features/progress/domain/progress_usecases.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';

void main() {
  group('strengthHighlight', () {
    final now = DateTime(2026, 11, 13, 12);
    ExerciseStats stats(List<(DateTime, double?)> points) => ExerciseStats(
      history: [
        for (final (date, kg) in points)
          HistoryPoint(date: date, workoutId: 'w', bestE1rmKg: kg),
      ],
    );

    test('the most recently trained with an e1RM, its latest', () {
      final highlight = strengthHighlight(
        {
          'squat': stats([(DateTime(2026, 11, 1), 120)]),
          // The latest workout's best, not the all-time best.
          'bench': stats([
            (DateTime(2026, 10, 30), 104),
            (DateTime(2026, 11, 10), 100),
          ]),
          // No e1RM, e.g. a plank: left out though the newest.
          'plank': stats([(DateTime(2026, 11, 12), null)]),
        },
        now: now,
        weeks: 12,
      );

      expect(highlight?.exerciseId, 'bench');
      expect(highlight?.e1rmKg, 100);
    });

    test('changes since the first e1RM of the last 12 weeks', () {
      final highlight = strengthHighlight(
        {
          'bench': stats([
            // Before the 12 weeks: not the start.
            (DateTime(2026, 8, 1), 90),
            (DateTime(2026, 9, 18), 101),
            (DateTime(2026, 11, 13), 104),
          ]),
        },
        now: now,
        weeks: 12,
      );

      expect(highlight?.change, (kg: 3.0, weeks: 8));
      expect(highlight?.trend, [101, 104]);
    });

    test('one e1RM in the 12 weeks has no change', () {
      final highlight = strengthHighlight(
        {
          'bench': stats([
            (DateTime(2026, 8, 1), 90),
            (DateTime(2026, 11, 10), 100),
          ]),
        },
        now: now,
        weeks: 12,
      );
      expect(highlight?.change, isNull);

      final old = strengthHighlight(
        {
          'bench': stats([
            (DateTime(2026, 6, 1), 90),
            (DateTime(2026, 7, 1), 95),
          ]),
        },
        now: now,
        weeks: 12,
      );
      expect(old?.change, isNull);
      expect(old?.trend, isEmpty);
    });

    test('over 2 weeks, only their e1RMs count', () {
      final highlight = strengthHighlight(
        {
          'bench': stats([
            // Before the 2 weeks, from midnight of October 30.
            (DateTime(2026, 10, 29, 23), 101),
            (DateTime(2026, 10, 30), 102),
            (DateTime(2026, 11, 13), 104),
          ]),
        },
        now: now,
        weeks: 2,
      );

      expect(highlight?.change, (kg: 2.0, weeks: 2));
      expect(highlight?.trend, [102, 104]);
    });

    test('ties go by id; none without stats', () {
      final day = DateTime(2026, 11, 10);
      final highlight = strengthHighlight(
        {
          'b': stats([(day, 1)]),
          'a': stats([(day, 2)]),
        },
        now: now,
        weeks: 12,
      );
      expect(highlight?.exerciseId, 'a');
      expect(strengthHighlight(const {}, now: now, weeks: 12), isNull);
    });
  });

  test('a card covers the free 2 weeks, 12 with Premium', () {
    expect(cardWeeks(null), 2);
    expect(cardWeeks(false), 2);
    expect(cardWeeks(true), 12);
  });

  group('bodySnapshot', () {
    final now = DateTime(2026, 11, 13, 12);
    BodyEntry entry(String id, DateTime date, {double? kg}) => BodyEntry(
      id: id,
      date: date,
      weightKg: kg,
      measurements: kg == null ? const {BodyMeasurement.waist: 80} : const {},
    );

    test('the latest weight, 12 weeks of them and the newest body fat', () {
      // Newest first, as the list holds them.
      final entries = [
        entry('e4', DateTime(2026, 11, 12), kg: 80),
        entry('e3', DateTime(2026, 11, 3)),
        entry('e2', DateTime(2026, 10, 1), kg: 82),
        entry('e1', DateTime(2026, 8, 1), kg: 85),
      ];

      final snapshot = bodySnapshot(
        entries,
        const {'e3': 18.5, 'e1': 20},
        now: now,
        weeks: 12,
      );

      expect(snapshot.latest, (date: DateTime(2026, 11, 12), kg: 80.0));
      // Over the 12 weeks' weights, not since the weigh-in before.
      expect(snapshot.change, (kg: -2.0, weeks: 6));
      // 1 August is more than 12 weeks back.
      expect(snapshot.weights, [
        (date: DateTime(2026, 10, 1), kg: 82.0),
        (date: DateTime(2026, 11, 12), kg: 80.0),
      ]);
      expect(snapshot.latestBodyFat, (
        date: DateTime(2026, 11, 3),
        percent: 18.5,
      ));
    });

    test('over 2 weeks, only their weights', () {
      final snapshot = bodySnapshot(
        [
          entry('e2', DateTime(2026, 11, 12), kg: 80),
          entry('e1', DateTime(2026, 10, 1), kg: 82),
        ],
        const {},
        now: now,
        weeks: 2,
      );

      expect(snapshot.weeks, 2);
      expect(snapshot.weights, [(date: DateTime(2026, 11, 12), kg: 80.0)]);
      expect(snapshot.change, isNull);
    });

    test('a single weigh-in has no change', () {
      final snapshot = bodySnapshot(
        [entry('e1', DateTime(2026, 11, 12), kg: 80)],
        const {},
        now: now,
        weeks: 12,
      );
      expect(snapshot.change, isNull);
    });

    test('nothing logged shows nothing', () {
      expect(
        bodySnapshot(const [], const {}, now: now, weeks: 2),
        const BodySnapshot(),
      );
    });
  });
}
