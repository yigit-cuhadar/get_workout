import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  final monday = DateTime(2026, 11, 9, 18);
  final wednesday = DateTime(2026, 11, 11, 18);
  final friday = DateTime(2026, 11, 13, 18);

  group('RecordKind.of', () {
    test('follows the logging type', () {
      expect(RecordKind.of(LoggingType.weightReps), {
        RecordKind.heaviestWeight,
        RecordKind.bestE1rm,
        RecordKind.bestSetVolume,
        RecordKind.mostReps,
      });
      expect(RecordKind.of(LoggingType.weightedBodyweight), {
        RecordKind.heaviestWeight,
        RecordKind.bestE1rm,
        RecordKind.bestSetVolume,
        RecordKind.mostReps,
      });
      expect(RecordKind.of(LoggingType.assistedBodyweight), {
        RecordKind.mostReps,
      });
      expect(RecordKind.of(LoggingType.reps), {RecordKind.mostReps});
      expect(RecordKind.of(LoggingType.duration), {RecordKind.longestDuration});
      expect(RecordKind.of(LoggingType.weightDuration), {
        RecordKind.heaviestWeight,
        RecordKind.longestDuration,
      });
    });
  });

  group('set calculations', () {
    test('volume is weight × reps with drops, only for loads', () {
      final drop = lift(
        100,
        5,
        type: SetType.drop,
        drops: const [Drop(weightKg: 80, reps: 5), Drop(weightKg: 60, reps: 4)],
      );
      expect(setVolume(drop, LoggingType.weightReps), 500 + 400 + 240);
      expect(setVolume(lift(20, 10), LoggingType.assistedBodyweight), 0);
      expect(
        setVolume(const WorkoutSet(reps: 8), LoggingType.weightedBodyweight),
        0,
      );
    });

    test('e1RM is Epley up to 12 reps, the weight itself for one', () {
      expect(setE1rm(lift(100, 1), LoggingType.weightReps), 100);
      expect(setE1rm(lift(100, 6), LoggingType.weightReps), 120);
      expect(setE1rm(lift(100, 13), LoggingType.weightReps), isNull);
      expect(setE1rm(lift(0, 5), LoggingType.weightReps), isNull);
      expect(setE1rm(lift(20, 5), LoggingType.assistedBodyweight), isNull);
    });

    test('bests skip warm-ups, undone sets and zero values', () {
      final bests = sessionBests([
        lift(140, 3, type: SetType.warmup),
        lift(150, 1, done: false),
        lift(100, 6),
        lift(90, 10),
      ], LoggingType.weightReps);
      expect(bests, {
        RecordKind.heaviestWeight: 100,
        RecordKind.bestE1rm: 120,
        RecordKind.bestSetVolume: 900,
        RecordKind.mostReps: 10,
      });
      expect(
        sessionBests([
          const WorkoutSet(reps: 12, done: true),
        ], LoggingType.weightedBodyweight),
        {RecordKind.mostReps: 12},
      );
      expect(
        sessionBests([
          const WorkoutSet(durationS: 60, done: true),
        ], LoggingType.duration),
        {RecordKind.longestDuration: 60},
      );
    });
  });

  group('applyWorkout', () {
    final first = workout('w1', [
      exercise('squat', [lift(100, 5), lift(100, 5)]),
    ], startedAt: monday);
    final better = workout('w2', [
      exercise('squat', [lift(110, 3), lift(80, 12)]),
    ], startedAt: wednesday);

    test('the first workout sets every record, last and history', () {
      final stats = applyWorkout(null, first, 'squat')!;
      expect(stats.records.keys, {
        RecordKind.heaviestWeight,
        RecordKind.bestE1rm,
        RecordKind.bestSetVolume,
        RecordKind.mostReps,
      });
      expect(
        stats.records[RecordKind.heaviestWeight],
        StatRecord(value: 100, date: monday, workoutId: 'w1'),
      );
      expect(
        stats.last,
        LastSession(
          date: monday,
          workoutId: 'w1',
          sets: [lift(100, 5), lift(100, 5)],
        ),
      );
      expect(stats.history, [
        HistoryPoint(
          date: monday,
          workoutId: 'w1',
          bestE1rmKg: 100 * (1 + 5 / 30),
          volumeKg: 1000,
        ),
      ]);
    });

    test('a later workout beats only what it beats', () {
      final stats = applyWorkout(
        applyWorkout(null, first, 'squat'),
        better,
        'squat',
      )!;
      expect(stats.records[RecordKind.heaviestWeight]!.workoutId, 'w2');
      expect(stats.records[RecordKind.mostReps]!.workoutId, 'w2');
      expect(stats.records[RecordKind.bestE1rm]!.workoutId, 'w2');
      // Per set: 80 × 12 beats 100 × 5.
      expect(stats.records[RecordKind.bestSetVolume]!.value, 960);
      expect(stats.last!.workoutId, 'w2');
      expect(stats.history.map((p) => p.workoutId), ['w1', 'w2']);
    });

    test('an equal value keeps the earlier record', () {
      final again = workout('w2', [
        exercise('squat', [lift(100, 5)]),
      ], startedAt: wednesday);
      final stats = applyWorkout(
        applyWorkout(null, first, 'squat'),
        again,
        'squat',
      )!;
      expect(stats.records[RecordKind.heaviestWeight]!.workoutId, 'w1');
    });

    test('an older workout added later does not become last time', () {
      final stats = applyWorkout(
        applyWorkout(null, better, 'squat'),
        first,
        'squat',
      )!;
      expect(stats.last!.workoutId, 'w2');
      expect(stats.history.map((p) => p.workoutId), ['w1', 'w2']);
    });

    test('applying the same workout twice changes nothing', () {
      final once = applyWorkout(null, first, 'squat');
      expect(applyWorkout(once, first, 'squat'), once);
    });

    test('combines every entry of the exercise, and skips undone ones', () {
      final twice = workout('w1', [
        exercise('squat', [lift(100, 5)]),
        exercise('bench', [lift(80, 5)]),
        exercise('squat', [lift(120, 2), lift(200, 1, done: false)]),
      ], startedAt: monday);
      final stats = applyWorkout(null, twice, 'squat')!;
      expect(stats.records[RecordKind.heaviestWeight]!.value, 120);
      expect(stats.last!.sets, [lift(100, 5), lift(120, 2)]);
      expect(stats.history.single.volumeKg, 740);
    });

    test('a warm-up-only session adds no point and keeps last', () {
      final before = applyWorkout(null, first, 'squat');
      final warmups = workout('w3', [
        exercise('squat', [lift(60, 5, type: SetType.warmup)]),
      ], startedAt: friday);
      expect(applyWorkout(before, warmups, 'squat'), same(before));
      final mixed = workout('w4', [
        exercise('squat', [lift(60, 5, type: SetType.warmup), lift(90, 5)]),
      ], startedAt: friday);
      expect(applyWorkout(before, mixed, 'squat')!.last!.sets, [lift(90, 5)]);
    });

    test('leaves the stats alone without a done set', () {
      final none = workout('w3', [
        exercise('squat', [lift(100, 5, done: false)]),
      ]);
      const stats = ExerciseStats();
      expect(applyWorkout(stats, none, 'squat'), same(stats));
      expect(applyWorkout(null, none, 'squat'), isNull);
    });

    test('history keeps the latest points only', () {
      final full = ExerciseStats(
        history: [
          for (var i = 0; i < ExerciseStats.maxHistory; i++)
            HistoryPoint(
              date: DateTime(2020).add(Duration(days: i)),
              workoutId: 'old$i',
            ),
        ],
      );
      final stats = applyWorkout(full, first, 'squat')!;
      expect(stats.history, hasLength(ExerciseStats.maxHistory));
      expect(stats.history.first.workoutId, 'old1');
      expect(stats.history.last.workoutId, 'w1');
    });
  });

  group('rebuildStats', () {
    test('equals applying the workouts in date order, given in any', () {
      final workouts = [
        workout('w3', [
          exercise('squat', [lift(90, 8)]),
        ], startedAt: friday),
        workout('w1', [
          exercise('squat', [lift(100, 5)]),
        ], startedAt: monday),
        workout('w2', [
          exercise('bench', [lift(70, 5)]),
        ], startedAt: wednesday),
      ];
      final expected = applyWorkout(
        applyWorkout(null, workouts[1], 'squat'),
        workouts[0],
        'squat',
      );
      expect(rebuildStats('squat', workouts), expected);
      expect(rebuildStats('row', workouts), isNull);
    });
  });

  group('beatenRecords', () {
    final first = workout('w1', [
      exercise('squat', [lift(100, 5)]),
    ], startedAt: monday);
    final next = workout('w2', [
      exercise('squat', [lift(105, 5)]),
    ], startedAt: wednesday);

    test('a first workout beats nothing', () {
      expect(
        beatenRecords(null, applyWorkout(null, first, 'squat'), first),
        isEmpty,
      );
    });

    test('lists the records the workout took over', () {
      final before = applyWorkout(null, first, 'squat');
      final after = applyWorkout(before, next, 'squat');
      expect(beatenRecords(before, after, next), [
        RecordKind.heaviestWeight,
        RecordKind.bestE1rm,
        RecordKind.bestSetVolume,
      ]);
      // Saving the same workout again is no new record.
      expect(
        beatenRecords(after, applyWorkout(after, next, 'squat'), next),
        isEmpty,
      );
    });
  });

  test('summarizeWorkout counts working sets, load volume and time', () {
    final done = workout(
      'w1',
      [
        exercise('squat', [lift(60, 5, type: SetType.warmup), lift(100, 5)]),
        exercise('pullup', [lift(20, 8)], type: LoggingType.assistedBodyweight),
        exercise('dip', [lift(10, 10)], type: LoggingType.weightedBodyweight),
      ],
      startedAt: monday,
      finishedAt: monday.add(const Duration(minutes: 52)),
    );
    expect(
      summarizeWorkout(done),
      const WorkoutSummary(
        duration: Duration(minutes: 52),
        volumeKg: 600,
        setCount: 3,
        exerciseCount: 3,
        muscleSets: {Muscle.quads: 3},
      ),
    );
  });

  group('summarizeWorkout records', () {
    final before = workout('w0', [
      exercise('squat', [lift(100, 5)]),
      exercise('bench', [lift(80, 8)]),
    ], startedAt: monday);
    final stats = {
      'squat': rebuildStats('squat', [before]),
      'bench': rebuildStats('bench', [before]),
    };
    Workout today(double squat, double bench) => workout('w1', [
      exercise('squat', [lift(squat - 20, 3), lift(squat, 5)]),
      exercise('bench', [lift(bench, 8)]),
    ], startedAt: monday.add(const Duration(days: 2)));
    WorkoutSummary summarize(Workout done) => summarizeWorkout(
      done,
      before: stats,
      after: {
        for (final id in ['squat', 'bench'])
          id: applyWorkout(stats[id], done, id)!,
      },
    );

    test('one row per exercise, its heaviest set and weight gain', () {
      final summary = summarize(today(102.5, 80));
      final record = summary.records.single;
      expect(record.exerciseId, 'squat');
      expect(record.set, lift(102.5, 5));
      expect(record.gain, (kind: RecordKind.heaviestWeight, amount: 2.5));
      expect(summary.closest, isNull);
    });

    test('none beaten: the closest heaviest weight', () {
      final summary = summarize(today(95, 77.5));
      expect(summary.records, isEmpty);
      expect(summary.closest, (name: 'bench', kg: 2.5));
      expect(summary.firstWorkout, isFalse);
    });

    test('nothing done before: records start now', () {
      final done = today(100, 80);
      final summary = summarizeWorkout(
        done,
        before: {'squat': null, 'bench': null},
      );
      expect(summary.firstWorkout, isTrue);
      expect(summary.records, isEmpty);
    });
  });

  group('heldRecordSets', () {
    StatRecord held(double value, String id) =>
        StatRecord(value: value, date: monday, workoutId: id);

    test('tags the first working set with a record this workout holds', () {
      final push = workout('w1', [
        exercise('bench', [
          lift(40, 10, type: SetType.warmup),
          lift(80, 8),
          lift(80, 8),
          lift(75, 10),
        ]),
        exercise('row', [lift(60, 10)]),
      ]);
      final stats = {
        'bench': ExerciseStats(
          records: {
            RecordKind.heaviestWeight: held(80, 'w1'),
            RecordKind.mostReps: held(10, 'w1'),
            RecordKind.bestE1rm: held(120, 'w0'),
          },
        ),
        'row': ExerciseStats(
          records: {RecordKind.heaviestWeight: held(70, 'w0')},
        ),
      };
      expect(heldRecordSets(push, stats), {(0, 1), (0, 3)});
    });

    test('no stats, no records', () {
      final push = workout('w1', [
        exercise('bench', [lift(80, 8)]),
      ]);
      expect(heldRecordSets(push, const {}), isEmpty);
    });
  });
}
