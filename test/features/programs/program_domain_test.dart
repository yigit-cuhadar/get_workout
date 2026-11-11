import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_editing.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockProgramRepository extends Mock implements ProgramRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(program());
    registerFallbackValue(
      ActiveProgram(
        programId: 'x',
        weekdays: const [1],
        nextDayIndex: 0,
        nextDate: CalendarDate(2026, 1, 1),
        startedAt: DateTime(2026),
      ),
    );
  });

  group('LoggingType targets', () {
    test('duration types take a duration, the rest a rep range', () {
      expect(
        {
          for (final type in LoggingType.values)
            if (type.isDurationBased) type,
        },
        {LoggingType.duration, LoggingType.weightDuration},
      );
    });

    test('every type that logs a weight can have a target', () {
      expect(
        {
          for (final type in LoggingType.values)
            if (type.logsWeight) type,
        },
        {
          LoggingType.weightReps,
          LoggingType.weightedBodyweight,
          LoggingType.assistedBodyweight,
          LoggingType.weightDuration,
        },
      );
    });
  });

  group('validateProgram', () {
    test('a sound program has no issues', () {
      expect(validateProgram(program(), loggingTypes).isValid, isTrue);
    });

    test('the name is required, trimmed, and at most 60 characters', () {
      Set<ProgramIssue> issues(String name) =>
          validateProgram(program(name: name), loggingTypes).program;
      expect(issues('   '), {ProgramIssue.nameMissing});
      expect(issues('x' * 60), isEmpty);
      expect(issues(' ${'x' * 60} '), isEmpty);
      expect(issues('x' * 61), {ProgramIssue.nameTooLong});
    });

    test('a length runs 1 to 52 weeks, or is left out', () {
      Set<ProgramIssue> issues(int? weeks) =>
          validateProgram(program(lengthWeeks: weeks), loggingTypes).program;
      expect(issues(null), isEmpty);
      expect(issues(1), isEmpty);
      expect(issues(52), isEmpty);
      expect(issues(0), {ProgramIssue.lengthWeeksOutOfRange});
      expect(issues(53), {ProgramIssue.lengthWeeksOutOfRange});
    });

    test('a program has 1 to 7 days', () {
      Program withDays(int count) => program().copyWith(
        days: [
          for (var i = 0; i < count; i++) ProgramDay(items: [item('a')]),
        ],
      );
      expect(validateProgram(withDays(0), loggingTypes).program, {
        ProgramIssue.noDays,
      });
      expect(validateProgram(withDays(7), loggingTypes).isValid, isTrue);
      expect(validateProgram(withDays(8), loggingTypes).program, {
        ProgramIssue.tooManyDays,
      });
    });

    test('a day has 1 to 20 items and a name of at most 40', () {
      ProgramValidation of(ProgramDay day) =>
          validateProgram(program().copyWith(days: [day]), loggingTypes);
      expect(of(const ProgramDay()).dayIssues(0), {DayIssue.noItems});
      expect(
        of(ProgramDay(items: [for (var i = 0; i < 20; i++) item('a')])).isValid,
        isTrue,
      );
      expect(
        of(ProgramDay(items: [for (var i = 0; i < 21; i++) item('a')]))
            .dayIssues(0),
        {DayIssue.tooManyItems},
      );
      expect(of(ProgramDay(name: 'x' * 41, items: [item('a')])).dayIssues(0), {
        DayIssue.nameTooLong,
      });
      expect(of(ProgramDay(items: [item('a')])).isValid, isTrue);
    });

    test('item issues are reported at their day and position', () {
      final validation = validateProgram(
        program().copyWith(
          days: [
            ProgramDay(items: [item('a')]),
            ProgramDay(items: [item('a'), item('a', sets: 0)]),
          ],
        ),
        loggingTypes,
      );
      expect(validation.items.keys, [(day: 1, item: 1)]);
      expect(validation.itemIssues(1, 1), {ItemIssue.setsOutOfRange});
    });

    test('an exercise not in the catalogue is unavailable', () {
      final validation = validateProgram(
        program().copyWith(
          days: [
            ProgramDay(items: [item('retired')]),
          ],
        ),
        loggingTypes,
      );
      expect(validation.itemIssues(0, 0), {ItemIssue.exerciseUnavailable});
    });
  });

  group('validateItem', () {
    const reps = LoggingType.weightReps;

    test('sets run 1 to 10', () {
      expect(validateItem(item('a', sets: 1), reps), isEmpty);
      expect(validateItem(item('a', sets: 10), reps), isEmpty);
      expect(validateItem(item('a', sets: 0), reps), {
        ItemIssue.setsOutOfRange,
      });
      expect(validateItem(item('a', sets: 11), reps), {
        ItemIssue.setsOutOfRange,
      });
    });

    test('a rep range runs 1 to 100 with min at most max', () {
      expect(validateItem(item('a', repMin: 1, repMax: 100), reps), isEmpty);
      expect(validateItem(item('a', repMin: 5, repMax: 5), reps), isEmpty);
      expect(validateItem(item('a', repMin: 0, repMax: 5), reps), {
        ItemIssue.repsOutOfRange,
      });
      expect(validateItem(item('a', repMin: 5, repMax: 101), reps), {
        ItemIssue.repsOutOfRange,
      });
      expect(validateItem(item('a', repMin: 12, repMax: 8), reps), {
        ItemIssue.repRangeInverted,
      });
    });

    test('rep-based exercises need both ends of the range', () {
      for (final type in [
        LoggingType.reps,
        LoggingType.weightReps,
        LoggingType.weightedBodyweight,
        LoggingType.assistedBodyweight,
      ]) {
        expect(validateItem(item('a', repMax: null), type), {
          ItemIssue.repsMissing,
        }, reason: type.code);
      }
    });

    test('duration-based exercises need 5 s to 60 min and no reps', () {
      for (final type in [LoggingType.duration, LoggingType.weightDuration]) {
        ProgramItem timed(int? seconds) =>
            item('a', repMin: null, repMax: null, durationS: seconds);
        expect(validateItem(timed(5), type), isEmpty);
        expect(validateItem(timed(3600), type), isEmpty);
        expect(validateItem(timed(null), type), {ItemIssue.durationMissing});
        expect(validateItem(timed(4), type), {ItemIssue.durationOutOfRange});
        expect(validateItem(timed(3601), type), {ItemIssue.durationOutOfRange});
        expect(validateItem(item('a', durationS: 30), type), {
          ItemIssue.wrongTarget,
        });
      }
    });

    test('a duration on a rep-based exercise is wrong', () {
      expect(validateItem(item('a', durationS: 30), reps), {
        ItemIssue.wrongTarget,
      });
    });

    test('rest runs 0 to 600 s', () {
      expect(validateItem(item('a', restS: 0), reps), isEmpty);
      expect(validateItem(item('a', restS: 600), reps), isEmpty);
      expect(validateItem(item('a', restS: -1), reps), {
        ItemIssue.restOutOfRange,
      });
      expect(validateItem(item('a', restS: 601), reps), {
        ItemIssue.restOutOfRange,
      });
    });

    test('a target weight runs 0 to 1000 kg, NaN never fits', () {
      expect(validateItem(item('a', targetKg: 0), reps), isEmpty);
      expect(validateItem(item('a', targetKg: 1000), reps), isEmpty);
      expect(validateItem(item('a', targetKg: 1000.1), reps), {
        ItemIssue.targetOutOfRange,
      });
      expect(validateItem(item('a', targetKg: double.nan), reps), {
        ItemIssue.targetOutOfRange,
      });
    });

    test('only exercises that log a weight take a target', () {
      expect(validateItem(item('a', targetKg: 20), LoggingType.reps), {
        ItemIssue.wrongTarget,
      });
      final hold = item('a', repMin: null, repMax: null, durationS: 30);
      expect(
        validateItem(hold.copyWith(targetKg: () => 10), LoggingType.duration),
        {ItemIssue.wrongTarget},
      );
      expect(
        validateItem(
          hold.copyWith(targetKg: () => 10),
          LoggingType.weightDuration,
        ),
        isEmpty,
      );
      expect(
        validateItem(item('a', targetKg: 15), LoggingType.assistedBodyweight),
        isEmpty,
      );
    });

    test('without a logging type only ranges are checked', () {
      expect(validateItem(item('a', repMin: null, durationS: 30), null), {
        ItemIssue.exerciseUnavailable,
      });
      expect(validateItem(item('a', sets: 0), null), {
        ItemIssue.exerciseUnavailable,
        ItemIssue.setsOutOfRange,
      });
    });
  });

  group('group rules', () {
    test('adjacent items of a group of two or more are fine', () {
      expect(
        invalidGroupIndexes([
          item('a', group: 'A'),
          item('b', group: 'A'),
          item('c'),
          item('d', group: 'B'),
          item('a', group: 'B'),
          item('b', group: 'B'),
        ]),
        isEmpty,
      );
    });

    test('a group of one is invalid', () {
      expect(invalidGroupIndexes([item('a', group: 'A'), item('b')]), {0});
    });

    test('a group split by another item is invalid', () {
      expect(
        invalidGroupIndexes([
          item('a', group: 'A'),
          item('b', group: 'A'),
          item('c'),
          item('d', group: 'A'),
        ]),
        {0, 1, 3},
      );
    });

    test('show as item issues', () {
      final validation = validateProgram(
        program().copyWith(
          days: [
            ProgramDay(
              items: [
                item('a', group: 'A'),
                item('b'),
              ],
            ),
          ],
        ),
        loggingTypes,
      );
      expect(validation.itemIssues(0, 0), {ItemIssue.groupInvalid});
    });
  });

  group('defaultItem', () {
    test('3 sets of 8-12 reps with the exercise rest', () {
      expect(
        defaultItem(move('squat', rest: 150)),
        const ProgramItem(
          exerciseId: 'squat',
          sets: 3,
          repMin: 8,
          repMax: 12,
          restS: 150,
        ),
      );
    });

    test('3 sets of 30 s for duration exercises', () {
      for (final type in [LoggingType.duration, LoggingType.weightDuration]) {
        expect(
          defaultItem(move('plank', type: type, rest: 45)),
          const ProgramItem(
            exerciseId: 'plank',
            sets: 3,
            durationS: 30,
            restS: 45,
          ),
        );
      }
    });

    test('the rest is kept inside the limits', () {
      expect(defaultItem(move('a', rest: 900)).restS, 600);
      expect(defaultItem(move('a', rest: -5)).restS, 0);
    });

    test('is always valid for its exercise', () {
      for (final type in LoggingType.values) {
        expect(validateItem(defaultItem(move('a', type: type)), type), isEmpty);
      }
    });
  });

  group('fitToLoggingType', () {
    test('an item that fits is returned as it is', () {
      final fitting = item('a', targetKg: 50);
      expect(
        identical(fitToLoggingType(fitting, LoggingType.weightReps), fitting),
        isTrue,
      );
    });

    test('reps become a duration and back, keeping sets, rest and group', () {
      final reps = item('a', sets: 4, restS: 30, group: 'A', targetKg: 20);
      expect(
        fitToLoggingType(reps, LoggingType.duration),
        const ProgramItem(
          exerciseId: 'a',
          sets: 4,
          durationS: 30,
          restS: 30,
          group: 'A',
        ),
      );
      final timed = item('a', repMin: null, repMax: null, durationS: 45);
      expect(fitToLoggingType(timed, LoggingType.reps), item('a'));
    });

    test('keeps what fits of a mixed item', () {
      final mixed = item('a', repMin: 5, repMax: 6, durationS: 40);
      expect(
        fitToLoggingType(mixed, LoggingType.reps),
        item('a', repMin: 5, repMax: 6),
      );
      expect(
        fitToLoggingType(mixed, LoggingType.weightDuration),
        item('a', repMin: null, repMax: null, durationS: 40),
      );
    });

    test('the result always passes the logging type\'s checks', () {
      for (final stored in [
        item('a', targetKg: 30),
        item('a', repMax: null),
        item('a', repMin: null, repMax: null),
        item('a', durationS: 40, targetKg: 10),
      ]) {
        for (final type in LoggingType.values) {
          expect(
            validateItem(fitToLoggingType(stored, type), type),
            isEmpty,
            reason: '$stored as $type',
          );
        }
      }
    });
  });

  group('replaceExercise', () {
    final current = item(
      'a',
      sets: 5,
      repMin: 3,
      repMax: 5,
      restS: 180,
    ).copyWith(targetKg: () => 100, group: () => 'A');

    test('keeps sets, rest, group and targets of the same kind', () {
      expect(
        replaceExercise(current, move('b')),
        current.copyWith(exerciseId: 'b'),
      );
    });

    test('switches to a duration for a duration exercise', () {
      expect(
        replaceExercise(current, move('plank', type: LoggingType.duration)),
        const ProgramItem(
          exerciseId: 'plank',
          sets: 5,
          durationS: 30,
          restS: 180,
          group: 'A',
        ),
      );
    });

    test('drops the target when the new exercise logs no weight', () {
      final next = replaceExercise(current, move('p', type: LoggingType.reps));
      expect(next.targetKg, isNull);
      expect(next.repMin, 3);
      expect(validateItem(next, LoggingType.reps), isEmpty);
    });

    test('the result is valid for the new exercise', () {
      for (final from in LoggingType.values) {
        for (final to in LoggingType.values) {
          final start = defaultItem(move('a', type: from));
          final next = replaceExercise(start, move('b', type: to));
          expect(validateItem(next, to), isEmpty, reason: '$from -> $to');
        }
      }
    });
  });

  group('grouping', () {
    List<String?> groups(List<ProgramItem> items) => [
      for (final i in items) i.group,
    ];
    List<String> ids(List<ProgramItem> items) => [
      for (final i in items) i.exerciseId,
    ];
    final plain = [item('a'), item('b'), item('c'), item('d')];

    test('linking two items makes a superset', () {
      final linked = linkWithNext(plain, 1);
      expect(groups(linked), [null, 'A', 'A', null]);
      expect(linkedSize(plain, 1), 2);
    });

    test('linking a group with the next item makes a circuit', () {
      final superset = linkWithNext(plain, 0);
      expect(linkedSize(superset, 1), 3);
      expect(groups(linkWithNext(superset, 1)), ['A', 'A', 'A', null]);
      expect(groups(linkWithNext(superset, 0)), ['A', 'A', 'A', null]);
    });

    test('linking two groups merges them', () {
      final two = linkWithNext(linkWithNext(plain, 0), 2);
      expect(groups(two), ['A', 'A', 'B', 'B']);
      expect(linkedSize(two, 1), 4);
      expect(groups(linkWithNext(two, 1)), ['A', 'A', 'A', 'A']);
    });

    test('groups are lettered in order', () {
      final linked = linkWithNext(linkWithNext(plain, 2), 0);
      expect(groups(linked), ['A', 'A', 'B', 'B']);
    });

    test('ungrouping dissolves the whole group', () {
      final circuit = linkWithNext(linkWithNext(plain, 0), 1);
      expect(groups(ungroup(circuit, 1)), [null, null, null, null]);
      expect(ungroup(plain, 2), plain);
    });

    test('removing an item leaves a group of one ungrouped', () {
      final linked = linkWithNext(linkWithNext(plain, 0), 2);
      final removed = removeItem(linked, 0);
      expect(ids(removed), ['b', 'c', 'd']);
      expect(groups(removed), [null, 'A', 'A']);
    });

    test('removing from a circuit keeps a superset', () {
      final circuit = linkWithNext(linkWithNext(plain, 0), 1);
      expect(groups(removeItem(circuit, 1)), ['A', 'A', null]);
    });

    test('relabelling repairs groups split in stored data', () {
      expect(
        groups(
          relabelGroups([
            item('a', group: 'X'),
            item('b'),
            item('c', group: 'X'),
            item('d', group: 'X'),
          ]),
        ),
        [null, null, 'A', 'A'],
      );
    });
  });

  group('moveItem', () {
    List<String> ids(List<ProgramItem> items) => [
      for (final i in items) i.exerciseId,
    ];
    List<String?> groups(List<ProgramItem> items) => [
      for (final i in items) i.group,
    ];
    // x, [a b], y, [c d e]
    final items = [
      item('x'),
      item('a', group: 'A'),
      item('b', group: 'A'),
      item('y'),
      item('c', group: 'B'),
      item('d', group: 'B'),
      item('e', group: 'B'),
    ];

    test('a plain item moves like in any list', () {
      final plain = [item('a'), item('b'), item('c')];
      expect(ids(moveItem(plain, 0, 2)), ['b', 'c', 'a']);
      expect(ids(moveItem(plain, 2, 0)), ['c', 'a', 'b']);
      expect(moveItem(plain, 1, 1), plain);
    });

    test('an item moves within its own group', () {
      final moved = moveItem(items, 4, 6);
      expect(ids(moved), ['x', 'a', 'b', 'y', 'd', 'e', 'c']);
      expect(groups(moved), groups(items));
    });

    test('dragging a grouped item out moves its whole group', () {
      final down = moveItem(items, 1, 3);
      expect(ids(down), ['x', 'y', 'a', 'b', 'c', 'd', 'e']);
      expect(groups(down), [null, null, 'A', 'A', 'B', 'B', 'B']);
      final up = moveItem(items, 5, 0);
      expect(ids(up), ['c', 'd', 'e', 'x', 'a', 'b', 'y']);
      expect(groups(up), ['A', 'A', 'A', null, 'B', 'B', null]);
    });

    test('an item never lands inside another group', () {
      // Down onto the middle of [c d e]: after the group.
      expect(ids(moveItem(items, 3, 5)), ['x', 'a', 'b', 'c', 'd', 'e', 'y']);
      // Up onto the middle of [a b]: before the group.
      expect(ids(moveItem(items, 3, 2)), ['x', 'y', 'a', 'b', 'c', 'd', 'e']);
      // Down onto [a b] from above: after it.
      expect(ids(moveItem(items, 0, 1)), ['a', 'b', 'x', 'y', 'c', 'd', 'e']);
    });

    test('groups stay valid after every possible move', () {
      for (var from = 0; from < items.length; from++) {
        for (var to = 0; to < items.length; to++) {
          final moved = moveItem(items, from, to);
          expect(invalidGroupIndexes(moved), isEmpty, reason: '$from->$to');
          expect(ids(moved).toSet(), ids(items).toSet());
        }
      }
    });
  });

  group('estimateDay', () {
    test('per set: 3 s per mid-range rep plus rest', () {
      // 3 × (10 reps × 3 s + 60 s)
      final day = ProgramDay(items: [item('a', restS: 60)]);
      expect(estimateDay(day), const Duration(seconds: 270));
    });

    test('a duration set takes its duration', () {
      final day = ProgramDay(
        items: [
          item('plank', repMin: null, repMax: null, durationS: 45, restS: 30),
        ],
      );
      expect(estimateDay(day), const Duration(seconds: 225));
    });

    test('a group rests only after each round', () {
      // Work: 3 × 30 + 4 × 30 = 210 s; rest: 4 rounds × 120 s.
      final day = ProgramDay(
        items: [
          item('a', restS: 0, group: 'A'),
          item('b', sets: 4, restS: 120, group: 'A'),
        ],
      );
      expect(estimateDay(day), const Duration(seconds: 210 + 480));
    });

    test('adds up the items of the day', () {
      final day = ProgramDay(
        items: [item('a', restS: 60), item('b', restS: 60)],
      );
      expect(estimateDay(day), const Duration(seconds: 540));
      expect(estimateDay(const ProgramDay()), Duration.zero);
    });
  });

  group('Program.duplicate', () {
    test('copies the content as a new program of the user', () {
      final original = Program(
        id: 'p1',
        name: 'PPL',
        origin: ProgramOrigin.catalog,
        sourceId: 'c1',
        lengthWeeks: 8,
        days: program().days,
      );
      final copy = original.duplicate('PPL (copy)');
      expect(copy.id, isNull);
      expect(copy.origin, ProgramOrigin.own);
      expect(copy.sourceId, isNull);
      expect(copy.name, 'PPL (copy)');
      expect(copy.lengthWeeks, 8);
      expect(copy.days, original.days);
    });

    test('cuts the name to the limit', () {
      final copy = program().duplicate('${'x' * 58} (copy)');
      expect(copy.name.length, ProgramLimits.maxNameLength);
    });
  });

  group('use cases', () {
    late MockProgramRepository repository;

    setUp(() {
      repository = MockProgramRepository();
      when(() => repository.createProgram(any(), any()))
          .thenAnswer((_) async => const Ok('new'));
      when(() => repository.updateProgram(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      when(
        () => repository.deleteProgram(
          any(),
          any(),
          clearActive: any(named: 'clearActive'),
        ),
      ).thenAnswer((_) async => const Ok(null));
      when(() => repository.startProgram(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => repository.updateActiveProgram(any(), any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test('a new program is created with its name trimmed', () async {
      final result = await SaveProgram(repository)((
        uid: 'u1',
        program: program(name: '  Upper Lower '),
        loggingTypes: loggingTypes,
      ));
      expect(result.valueOrNull, 'new');
      verify(() => repository.createProgram('u1', program())).called(1);
    });

    test('a stored program is updated and keeps its id', () async {
      final result = await SaveProgram(repository)((
        uid: 'u1',
        program: program(id: 'p1'),
        loggingTypes: loggingTypes,
      ));
      expect(result.valueOrNull, 'p1');
      verify(() => repository.updateProgram('u1', program(id: 'p1'))).called(1);
    });

    test('an invalid program never reaches the repository', () async {
      final result = await SaveProgram(repository)((
        uid: 'u1',
        program: program(name: ''),
        loggingTypes: loggingTypes,
      ));
      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repository.createProgram(any(), any()));
    });

    test('deleting the active program also stops it', () async {
      final delete = DeleteProgram(repository);
      await delete((uid: 'u1', id: 'p1', activeProgramId: 'p1'));
      await delete((uid: 'u1', id: 'p2', activeProgramId: 'p1'));
      await delete((uid: 'u1', id: 'p3', activeProgramId: null));
      verify(() => repository.deleteProgram('u1', 'p1', clearActive: true))
          .called(1);
      verify(() => repository.deleteProgram('u1', 'p2', clearActive: false))
          .called(1);
      verify(() => repository.deleteProgram('u1', 'p3', clearActive: false))
          .called(1);
    });

    test('starting plans the first day on the first weekday from today', () {
      // Wednesday 11 November 2026, 20:15.
      final now = DateTime(2026, 11, 11, 20, 15);
      final start = StartProgram(repository, clock: () => now);
      start((uid: 'u1', program: program(id: 'p1'), weekdays: const [5, 1]));
      verify(
        () => repository.startProgram(
          'u1',
          ActiveProgram(
            programId: 'p1',
            weekdays: const [1, 5],
            nextDayIndex: 0,
            nextDate: CalendarDate(2026, 11, 13),
            startedAt: now,
          ),
        ),
      ).called(1);
    });

    test('starting needs one distinct weekday per day', () async {
      final start = StartProgram(repository);
      for (final weekdays in [
        const [1],
        const [1, 3, 5],
        const [2, 2],
        const [0, 3],
        const [3, 8],
      ]) {
        final result = await start((
          uid: 'u1',
          program: program(id: 'p1'),
          weekdays: weekdays,
        ));
        expect(
          result.failureOrNull,
          isA<ValidationFailure>(),
          reason: '$weekdays',
        );
      }
      final unsaved = await start((
        uid: 'u1',
        program: program(),
        weekdays: const [1, 4],
      ));
      expect(unsaved.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repository.startProgram(any(), any()));
    });

    group('a missed day', () {
      // Mon/Thu; Monday's day 0 missed; today is Wednesday 11 November.
      final missed = ActiveProgram(
        programId: 'p1',
        weekdays: const [1, 4],
        nextDayIndex: 0,
        nextDate: CalendarDate(2026, 11, 9),
        startedAt: DateTime(2026, 11, 2),
      );
      ResolveMissedDay resolver() =>
          ResolveMissedDay(repository, clock: () => DateTime(2026, 11, 11, 9));

      test('is resolved by the chosen option', () async {
        for (final (choice, expected) in [
          (
            MissedDayChoice.doToday,
            missed.copyWith(nextDate: CalendarDate(2026, 11, 11)),
          ),
          (
            MissedDayChoice.moveToNextWeekday,
            missed.copyWith(nextDate: CalendarDate(2026, 11, 12)),
          ),
          (
            MissedDayChoice.skip,
            missed.copyWith(
              nextDayIndex: 1,
              nextDate: CalendarDate(2026, 11, 12),
            ),
          ),
        ]) {
          final result = await resolver()((
            uid: 'u1',
            active: missed,
            program: program(id: 'p1'),
            choice: choice,
          ));
          expect(result.isOk, isTrue);
          verify(() => repository.updateActiveProgram('u1', expected))
              .called(1);
        }
      });

      test('nothing is written when no day is missed', () async {
        final onTime = missed.copyWith(nextDate: CalendarDate(2026, 11, 12));
        for (final (active, current) in [
          (onTime, program(id: 'p1')),
          (missed, program(id: 'p2')),
          // Finished: a one-week program started on 2 November.
          (missed, program(id: 'p1', lengthWeeks: 1)),
        ]) {
          final result = await resolver()((
            uid: 'u1',
            active: active,
            program: current,
            choice: MissedDayChoice.doToday,
          ));
          expect(result.failureOrNull, isA<ValidationFailure>());
        }
        verifyNever(() => repository.updateActiveProgram(any(), any()));
      });
    });

    test('completing a day moves the program on', () async {
      final active = ActiveProgram(
        programId: 'p1',
        weekdays: const [1, 4],
        nextDayIndex: 1,
        nextDate: CalendarDate(2026, 11, 12),
        startedAt: DateTime(2026, 11, 2),
      );
      final complete = CompleteProgramDay(repository);
      await complete((
        uid: 'u1',
        active: active,
        dayCount: 2,
        dayIndex: 1,
        on: CalendarDate(2026, 11, 12),
      ));
      verify(
        () => repository.updateActiveProgram(
          'u1',
          active.copyWith(
            nextDayIndex: 0,
            nextDate: CalendarDate(2026, 11, 16),
          ),
        ),
      ).called(1);
      final refused = await complete((
        uid: 'u1',
        active: active,
        dayCount: 2,
        dayIndex: 2,
        on: CalendarDate(2026, 11, 12),
      ));
      expect(refused.failureOrNull, isA<ValidationFailure>());
    });

    test('changing weekdays replans the next day from today', () async {
      final active = ActiveProgram(
        programId: 'p1',
        weekdays: const [1, 4],
        nextDayIndex: 1,
        nextDate: CalendarDate(2026, 11, 12),
        startedAt: DateTime(2026, 11, 2),
      );
      final change = ChangeWeekdays(
        repository,
        clock: () => DateTime(2026, 11, 11, 9),
      );
      final refused = await change((
        uid: 'u1',
        active: active,
        dayCount: 2,
        weekdays: const [2],
      ));
      expect(refused.failureOrNull, isA<ValidationFailure>());
      await change((
        uid: 'u1',
        active: active,
        dayCount: 2,
        weekdays: const [2, 6],
      ));
      verify(
        () => repository.updateActiveProgram(
          'u1',
          active.copyWith(
            weekdays: const [2, 6],
            nextDate: CalendarDate(2026, 11, 14),
          ),
        ),
      ).called(1);
    });
  });
}
