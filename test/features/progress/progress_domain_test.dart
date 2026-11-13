import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/progress/domain/body_snapshot.dart';
import 'package:get_workout/features/progress/domain/progress_usecases.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../workout/fixtures.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  setUpAll(() => registerFallbackValue(CalendarDate(2026, 1, 1)));

  group('strengthHighlights', () {
    ExerciseStats stats({required DateTime last, double? e1rmKg}) =>
        ExerciseStats(
          records: {
            if (e1rmKg != null)
              RecordKind.bestE1rm: StatRecord(
                value: e1rmKg,
                date: last,
                workoutId: 'w',
              ),
          },
          history: [HistoryPoint(date: last, workoutId: 'w')],
        );

    test('the most recently trained with an e1RM, at most three', () {
      final highlights = strengthHighlights({
        'squat': stats(last: DateTime(2026, 11, 1), e1rmKg: 120),
        'bench': stats(last: DateTime(2026, 11, 10), e1rmKg: 90),
        // No e1RM, e.g. a plank: left out though the newest.
        'plank': stats(last: DateTime(2026, 11, 12)),
        'row': stats(last: DateTime(2026, 11, 5), e1rmKg: 80),
        'deadlift': stats(last: DateTime(2026, 10, 1), e1rmKg: 150),
      });

      expect(highlights, [
        (exerciseId: 'bench', e1rmKg: 90.0),
        (exerciseId: 'row', e1rmKg: 80.0),
        (exerciseId: 'squat', e1rmKg: 120.0),
      ]);
    });

    test('ties go by id; last time counts before the history', () {
      final day = DateTime(2026, 11, 10);
      final highlights = strengthHighlights({
        'b': stats(last: day, e1rmKg: 1),
        'a': stats(last: day, e1rmKg: 2),
        'c': ExerciseStats(
          records: {
            RecordKind.bestE1rm: StatRecord(
              value: 3,
              date: DateTime(2026, 1, 1),
              workoutId: 'w',
            ),
          },
          last: LastSession(
            date: DateTime(2026, 11, 11),
            workoutId: 'w',
            sets: const [],
          ),
        ),
      });

      expect([for (final h in highlights) h.exerciseId], ['c', 'a', 'b']);
    });

    test('none without stats', () {
      expect(strengthHighlights(const {}), isEmpty);
    });
  });

  test('WatchStrengthHighlights reads the user\'s stats', () async {
    final repository = MockWorkoutRepository();
    when(() => repository.watchAllStats('u1')).thenAnswer(
      (_) => Stream.value({
        'squat': ExerciseStats(
          records: {
            RecordKind.bestE1rm: StatRecord(
              value: 100,
              date: DateTime(2026, 11, 1),
              workoutId: 'w',
            ),
          },
          history: [HistoryPoint(date: DateTime(2026, 11, 1), workoutId: 'w')],
        ),
      }),
    );

    final (:top, :trained) = await WatchStrengthHighlights(repository)('u1')
        .first;
    expect(top, [(exerciseId: 'squat', e1rmKg: 100.0)]);
    expect(trained, isTrue);
  });

  test(
    'WatchWorkoutCountInMonth counts the workouts of the whole month',
    () async {
      final repository = MockWorkoutRepository();
      when(
        () => repository.watchWorkoutsBetween(
          any(),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) => Stream.value([workout('w1', const []), workout('w2', const [])]),
      );

      final count = await WatchWorkoutCountInMonth(repository)((
        uid: 'u1',
        day: CalendarDate(2026, 2, 14),
      )).first;

      expect(count, 2);
      verify(
        () => repository.watchWorkoutsBetween(
          'u1',
          from: CalendarDate(2026, 2, 1),
          to: CalendarDate(2026, 2, 28),
        ),
      ).called(1);
    },
  );

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

      final snapshot = bodySnapshot(entries, const {
        'e3': 18.5,
        'e1': 20,
      }, now: now);

      expect(snapshot.latestKg, 80);
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

    test('nothing logged shows nothing', () {
      expect(bodySnapshot(const [], const {}, now: now), const BodySnapshot());
    });
  });
}
