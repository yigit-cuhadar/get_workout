import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/data/firestore_body_repository.dart';
import 'package:get_workout/features/body/domain/entry_body_fat.dart';
import 'package:get_workout/features/cardio/data/firestore_cardio_repository.dart';
import 'package:get_workout/features/exercises/data/firestore_user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/data/firestore_profile_repository.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/programs/data/firestore_program_repository.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_editing.dart';

import '../../tool/src/content_import.dart' show decodeFields;
import '../../tool/src/content_validator.dart';
import '../../tool/src/demo_seed.dart';

/// [value] with every DateTime as the Timestamp the app writes.
Object? _firestore(Object? value) => switch (value) {
  DateTime() => Timestamp.fromDate(value),
  Map() => {
    for (final MapEntry(:key, value: v) in value.entries) key: _firestore(v),
  },
  List() => [for (final v in value) _firestore(v)],
  _ => value,
};

Map<String, dynamic> _doc(Map<String, Object?> map) =>
    (_firestore(map)! as Map).cast<String, dynamic>();

void main() {
  final content = demoContent(
    validateContent(
      Directory('content/exercises'),
      programs: Directory('content/programs'),
    ),
  );
  // A Sunday.
  final today = CalendarDate(2026, 11, 22);
  DemoSeed seedOn(CalendarDate today) => buildDemoSeed(
    today: today,
    programJson: content.program,
    catalogue: content.catalogue,
  );
  final seed = seedOn(today);

  List<(Workout, WorkoutExercise)> sessionsOf(DemoSeed seed, String id) => [
    for (final w in seed.workouts)
      for (final e in w.exercises)
        if (e.exerciseId == id) (w, e),
  ];

  group('dates', () {
    test('about 30 sessions over eight weeks on the training days, '
        'the last 1 to 3 days ago, on any weekday', () {
      for (var d = 0; d < 7; d++) {
        final day = today.addDays(d);
        final s = seedOn(day);
        expect(s.workouts, hasLength(30));
        final first = CalendarDate.of(s.workouts.first.startedAt);
        final last = CalendarDate.of(s.workouts.last.startedAt);
        expect(day.daysSince(first), inInclusiveRange(52, 56));
        expect(day.daysSince(last), inInclusiveRange(1, 3));
        for (final w in s.workouts) {
          final date = CalendarDate.of(w.startedAt);
          expect(demoSchedule[date.weekday], w.dayIndex);
          expect(w.programId, demoProgramId);
          expect(w.finishedAt!.isAfter(w.startedAt), isTrue);
          expect(
            w.finishedAt!.difference(w.startedAt).inMinutes,
            inInclusiveRange(35, 75),
          );
        }
      }
    });

    test('the next day is today or the next training day, with its own '
        'day, in week 9 of 10', () {
      for (var d = 0; d < 7; d++) {
        final day = today.addDays(d);
        final s = seedOn(day);
        final active = s.active;
        expect(active.programId, demoProgramId);
        expect(active.schedule, demoSchedule);
        expect(active.nextDate.isBefore(day), isFalse);
        expect(
          active.nextDate,
          ProgramSchedule.nextWeekday(demoSchedule.keys, from: day),
        );
        expect(active.nextDayIndex, demoSchedule[active.nextDate.weekday]);
        final schedule = ProgramSchedule(
          active,
          dayCount: s.program.days.length,
          lengthWeeks: s.program.lengthWeeks,
        );
        expect(schedule.week(day), 9);
        expect(schedule.isFinished(day), isFalse);
        expect(schedule.isMissed(day), isFalse);
      }
    });

    test('ids are unique and carry the demo prefix', () {
      final ids = [
        for (final w in seed.workouts) w.id,
        for (final e in seed.bodyEntries) e.id,
        for (final c in seed.cardio) c.id!,
        seed.program.id!,
      ];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id.startsWith(demoPrefix)), isTrue);
    });

    test('weigh-ins every few days from 85.5 to 82 kg, four measurement '
        'days, cardio on rest days in the last two weeks', () {
      final entries = seed.bodyEntries;
      expect(entries.first.weightKg, 85.5);
      expect(entries.last.weightKg, 82.0);
      expect(today.daysSince(CalendarDate.of(entries.last.date)), 2);
      expect(entries.where((e) => !e.isWeightOnly), hasLength(4));
      expect(entries.every((e) => e.photos.isEmpty), isTrue);
      for (final e in entries.where((e) => !e.isWeightOnly)) {
        expect(e.weightKg, isNotNull);
        expect(e.measurements.keys, containsAll(bodyFatMeasurements(Sex.male)));
      }
      expect(seed.cardio, hasLength(3));
      for (final c in seed.cardio) {
        final date = CalendarDate.of(c.date);
        expect(demoSchedule.containsKey(date.weekday), isFalse);
        expect(today.daysSince(date), inInclusiveRange(1, 14));
      }
    });
  });

  group('progression', () {
    test('bench press climbs from 70 to 82.5 kg, squat from 95 to 115', () {
      for (final (id, from, to) in [
        ('ex_barbell_bench_press', 70.0, 82.5),
        ('ex_barbell_back_squat', 95.0, 115.0),
      ]) {
        final kgs = [
          for (final (_, e) in sessionsOf(seed, id))
            e.sets.where((s) => !s.isWarmup).first.weightKg!,
        ];
        expect(kgs.first, from);
        expect(kgs.last, to);
      }
    });

    test('every load rises in its steps and never falls; reps stay in the '
        'program range', () {
      for (final MapEntry(key: id, value: plan) in loadPlans.entries) {
        final sessions = sessionsOf(seed, id);
        expect(sessions, isNotEmpty, reason: id);
        double? previous;
        for (final (_, exercise) in sessions) {
          final working = exercise.sets.where((s) => !s.isWarmup).toList();
          expect(working, hasLength(exercise.goal?.sets ?? working.length));
          final kg = working.first.weightKg!;
          expect(working.every((s) => s.weightKg == kg), isTrue);
          expect(((kg - plan.startKg) / plan.stepKg) % 1, 0, reason: id);
          if (previous != null) expect(kg, greaterThanOrEqualTo(previous));
          previous = kg;
        }
        expect(previous, plan.endKg, reason: id);
      }
      for (final w in seed.workouts) {
        final day = seed.program.days[w.dayIndex!];
        for (final e in w.exercises) {
          final item = day.items.firstWhere(
            (i) => i.exerciseId == e.exerciseId,
          );
          final working = e.sets.where((s) => !s.isWarmup).toList();
          expect(working, hasLength(item.sets));
          for (final set in working) {
            expect(set.reps, inInclusiveRange(item.repMin!, item.repMax!));
            expect(set.rir, inInclusiveRange(1, 2));
            expect(set.done, isTrue);
          }
        }
      }
    });

    test('the first two lifts of a day are warmed up at the suggested '
        'weights, the others not', () {
      final w = seed.workouts.first;
      final bench = w.exercises.first;
      expect(
        [
          for (final s in bench.sets.where((s) => s.isWarmup))
            (s.weightKg, s.reps),
        ],
        [(35.0, 8), (52.5, 4)],
      );
      expect(w.exercises[1].sets.where((s) => s.isWarmup), hasLength(2));
      for (final e in w.exercises.skip(2)) {
        expect(e.sets.where((s) => s.isWarmup), isEmpty);
      }
    });

    test('the stats show records, a rising history and the last session', () {
      final bench = rebuildStats('ex_barbell_bench_press', seed.workouts)!;
      final lastBench = sessionsOf(seed, 'ex_barbell_bench_press').last.$1;
      expect(bench.records[RecordKind.heaviestWeight]!.value, 82.5);
      expect(bench.records[RecordKind.heaviestWeight]!.workoutId, lastBench.id);
      expect(bench.history, hasLength(8));
      expect(bench.last!.workoutId, lastBench.id);
      expect(bench.outdated, isFalse);
      final e1rms = [for (final p in bench.history) p.bestE1rmKg!];
      expect(e1rms.last, greaterThan(e1rms.first));

      final records = [
        for (final (i, w) in seed.workouts.indexed)
          summarizeWorkout(
            w,
            before: {
              for (final id in w.exerciseIds)
                id: rebuildStats(id, seed.workouts.take(i)),
            },
            after: {
              for (final id in w.exerciseIds)
                id: rebuildStats(id, seed.workouts.take(i + 1))!,
            },
          ).records.length,
      ];
      expect(records.first, 0);
      expect(records.last, greaterThan(0));
      expect(records.where((n) => n > 0).length, greaterThan(20));
    });
  });

  group('documents', () {
    test('workouts are storable and written as the app writes them', () {
      for (final w in seed.workouts) {
        expect(isStorable(w), isTrue);
        expect(w.exercises.every((e) => e.goal == null), isTrue);
        final doc = _doc(workoutDoc(w));
        expect(doc, FirestoreWorkoutRepository.workoutToMap(w));
        expect(FirestoreWorkoutRepository.workoutFromMap(w.id, doc), w);
      }
    });

    test('stats are written as the app writes them', () {
      for (final id in seed.exerciseIds) {
        final stats = rebuildStats(id, seed.workouts)!;
        final doc = _doc(statsDoc(stats));
        expect(doc, FirestoreWorkoutRepository.statsToMap(stats));
        expect(FirestoreWorkoutRepository.statsFromMap(doc), stats);
      }
    });

    test('the program copy and the active program', () {
      final doc = _doc(programDoc(seed.program));
      expect(
        doc,
        Map.of(FirestoreProgramRepository.programToMap(seed.program))
          ..remove('updatedAt'),
      );
      final read = FirestoreProgramRepository.programFromMap(
        demoProgramId,
        doc,
      )!;
      expect(read, seed.program);
      expect(read.name, 'Upper/Lower 4-Day');
      expect(read.sourceId, sourceProgramId);
      expect(read.days, hasLength(4));

      final active = _doc(activeProgramMap(seed.active));
      expect(active, FirestoreProgramRepository.activeToMap(seed.active));
      expect(FirestoreProgramRepository.activeFromMap(active), seed.active);
    });

    test('body entries and cardio are written as the app writes them', () {
      for (final e in seed.bodyEntries) {
        final doc = _doc(bodyEntryDoc(e));
        expect(doc, FirestoreBodyRepository.toMap(e));
        expect(FirestoreBodyRepository.fromMap(e.id, doc), e);
      }
      for (final c in seed.cardio) {
        final doc = _doc(cardioDoc(c));
        expect(doc, FirestoreCardioRepository.toMap(c));
        expect(FirestoreCardioRepository.fromMap(c.id!, doc), c);
      }
    });

    test('the profile, onboarding and favourites read back', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('users/u').set({
        'profile': {...demoProfile, 'onboardingCompletedAt': Timestamp.now()},
        'favoriteExerciseIds': demoFavorites,
      });
      final profile = await FirestoreProfileRepository(firestore)
          .watchProfile('u')
          .first;
      expect(profile.goal, Goal.buildMuscle);
      expect(profile.level, Level.intermediate);
      expect(profile.daysPerWeek, 4);
      expect(profile.equipment, EquipmentProfile.fullGym.equipment);
      expect(profile.sex, Sex.male);
      expect(profile.birthYear, 1994);
      expect(profile.heightCm, 180);
      expect(profile.weightKg, 82);
      expect(profile.targetWeightKg, 78);
      expect(profile.onboardingCompletedAt, isNotNull);
      expect(
        await FirestoreUserLibraryRepository(firestore)
            .watchFavorites('u')
            .first,
        demoFavorites.toSet(),
      );
      for (final id in demoFavorites) {
        expect(content.catalogue, contains(id));
      }
    });

    test('REST values: timestamps in UTC, workouts read back from them', () {
      final at = DateTime(2026, 11, 20, 18, 30);
      expect(encodeDemoValue(at), {
        'timestampValue': at.toUtc().toIso8601String(),
      });
      expect(
        () => encodeDemoValue([
          [1],
        ]),
        throwsArgumentError,
      );
      for (final w in seed.workouts) {
        final decoded = decodeFields(encodeDemoFields(workoutDoc(w)));
        expect(workoutFromDoc(w.id, decoded), w);
      }
    });
  });

  group('writes', () {
    const db = 'projects/p/databases/(default)';
    String path(Map<String, Object?> write) => switch (write) {
      {'delete': final String name} => name,
      {'update': {'name': final String name}} => name,
      _ => throw StateError('$write'),
    };
    Set<String> deleted(List<Map<String, Object?>> writes) => {
      for (final w in writes)
        if (w['delete'] case final String name) name,
    };

    // Another workout of the user's own, with a heavier bench press.
    final own = seed.workouts.first.copyWith(
      exercises: [
        seed.workouts.first.exercises.first.copyWith(
          sets: [const WorkoutSet(weightKg: 100, reps: 3, done: true)],
        ),
      ],
    );
    final ownWorkout = Workout(
      id: 'abc',
      startedAt: own.startedAt,
      finishedAt: own.finishedAt,
      name: 'Own',
      exercises: own.exercises,
    );

    test('seeding writes every document once, replaces old demo documents '
        'and keeps the user\'s other workouts in the stats', () {
      final writes = seedWrites(db, 'u', seed, (
        demoPaths: {'users/u/workouts/demo_w99', 'users/u/workouts/demo_w01'},
        otherWorkouts: [ownWorkout],
      ));
      final paths = [for (final w in writes) path(w)];
      expect(paths.toSet(), hasLength(paths.length));
      expect(deleted(writes), {'$db/documents/users/u/workouts/demo_w99'});
      final docs = paths.map((p) => p.split('/documents/').last).toSet();
      expect(docs, containsAll(['users/u', 'users/u/programs/$demoProgramId']));
      for (final w in seed.workouts) {
        expect(docs, contains('users/u/workouts/${w.id}'));
      }
      for (final id in seed.exerciseIds) {
        expect(docs, contains('users/u/exerciseStats/$id'));
      }
      expect(
        writes.where((w) => path(w).contains('/bodyEntries/')),
        hasLength(seed.bodyEntries.length),
      );
      expect(
        writes.where((w) => path(w).contains('/cardio/')),
        hasLength(seed.cardio.length),
      );

      final bench = writes.firstWhere(
        (w) => path(w).endsWith('/exerciseStats/ex_barbell_bench_press'),
      );
      final records =
          decodeFields(
                (bench['update']! as Map)['fields'] as Map<String, Object?>,
              )['records']!
              as Map;
      expect((records['heaviestWeight'] as Map)['value'], 100.0);

      final user = writes.firstWhere((w) => path(w).endsWith('/users/u'));
      expect((user['updateMask']! as Map)['fieldPaths'], [
        for (final key in demoProfile.keys) 'profile.$key',
        'activeProgram',
      ]);
      expect(user['updateTransforms'], [
        {
          'fieldPath': 'profile.onboardingCompletedAt',
          'setToServerValue': 'REQUEST_TIME',
        },
        {
          'fieldPath': 'favoriteExerciseIds',
          'appendMissingElements': {
            'values': [
              for (final id in demoFavorites) {'stringValue': id},
            ],
          },
        },
      ]);
    });

    test('clearing removes the demo documents, rebuilds or deletes the '
        'stats and stops only the demo program', () {
      final demoPaths = {
        'users/u/workouts/demo_w01',
        'users/u/programs/$demoProgramId',
      };
      final writes = clearWrites(
        db,
        'u',
        (demoPaths: demoPaths, otherWorkouts: [ownWorkout]),
        (exists: true, activeProgramId: demoProgramId),
        demoExerciseIds: seed.exerciseIds,
      );
      expect(deleted(writes), {
        for (final p in demoPaths) '$db/documents/$p',
        for (final id in seed.exerciseIds)
          if (id != 'ex_barbell_bench_press')
            '$db/documents/users/u/exerciseStats/$id',
      });
      final user = writes.firstWhere((w) => path(w).endsWith('/users/u'));
      expect((user['updateMask']! as Map)['fieldPaths'], ['activeProgram']);
      expect(
        (user['updateTransforms']! as List).single,
        containsPair('fieldPath', 'favoriteExerciseIds'),
      );

      final other = clearWrites(
        db,
        'u',
        (demoPaths: demoPaths, otherWorkouts: const []),
        (exists: true, activeProgramId: 'own'),
        demoExerciseIds: const {},
      );
      final otherUser = other.firstWhere((w) => path(w).endsWith('/users/u'));
      expect((otherUser['updateMask']! as Map)['fieldPaths'], isEmpty);

      final none = clearWrites(
        db,
        'u',
        (demoPaths: const {}, otherWorkouts: const []),
        (exists: false, activeProgramId: null),
        demoExerciseIds: const {},
      );
      expect(none, isEmpty);
    });
  });
}
