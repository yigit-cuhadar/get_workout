import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/today/presentation/next_workout.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';

import '../programs/fixtures.dart';

void main() {
  final upperLower = program(id: 'p1');
  final premiumCopy = program(id: 'p1', premium: true);
  final active = ActiveProgram(
    programId: 'p1',
    schedule: const {1: 0, 4: 1},
    nextDayIndex: 1,
    nextDate: CalendarDate(2026, 11, 12),
    startedAt: DateTime(2026, 11, 2),
  );
  final missed = PlannedDay(
    date: CalendarDate(2026, 11, 12),
    dayIndex: 1,
    status: PlannedStatus.missed,
  );

  ProgramListState ready({
    List<Program>? programs,
    ActiveProgram? activeProgram,
    bool finished = false,
    CalendarDate? nextDate,
    PlannedDay? missedDay,
    CalendarDate? moveDate,
    bool? premium = false,
  }) => ProgramListState(
    status: ProgramListStatus.ready,
    programs: programs ?? [upperLower],
    active: activeProgram,
    finished: finished,
    nextDate: nextDate,
    missed: missedDay,
    moveDate: moveDate,
    premium: premium,
  );

  /// The name a day gives the workout it starts, as on the page.
  String startName(Program program, int dayIndex) =>
      '${program.name} · ${program.days[dayIndex].name}';

  /// Thursday 12 November 2026, nothing finished yet.
  final thursday = CalendarDate(2026, 11, 12);

  NextWorkout? next(
    ProgramListState state,
    ActiveWorkoutState workout, {
    List<Workout>? done = const [],
  }) => nextWorkoutOf(
    state,
    activeWorkoutViewOf(workout),
    startName: startName,
    today: (today: thursday, done: done),
  );

  /// No workout in progress.
  NextWorkout? idle(ProgramListState state, {List<Workout>? done = const []}) =>
      next(
        state,
        const ActiveWorkoutState(status: WorkoutStatus.none),
        done: done,
      );

  const exercise = WorkoutExercise(
    exerciseId: 'a',
    name: 'Bench press',
    loggingType: LoggingType.weightReps,
  );

  ActiveWorkoutState running(Workout workout) =>
      ActiveWorkoutState(status: WorkoutStatus.active, workout: workout);

  group('a workout in progress', () {
    final started = DateTime(2026, 11, 12, 18);
    final lower = Workout(
      id: 'w1',
      startedAt: started,
      programId: 'p1',
      dayIndex: 1,
      name: 'Upper Lower · Lower',
      exercises: const [exercise],
    );

    /// Not from a program day, with nothing done.
    WorkoutInProgress inProgress(String name) => WorkoutInProgress(
      name: name,
      startedAt: started,
      exercise: 1,
      exercises: 1,
      doneSets: 0,
    );

    test('comes first, with the program day it was started from', () {
      expect(
        next(
          ready(activeProgram: active, nextDate: CalendarDate(2026, 11, 12)),
          running(lower),
        ),
        WorkoutInProgress(
          name: 'Upper Lower · Lower',
          startedAt: started,
          exercise: 1,
          exercises: 1,
          doneSets: 0,
          program: upperLower,
          dayIndex: 1,
        ),
      );
    });

    test('also while finishing, and while the list loads', () {
      expect(
        next(
          const ProgramListState(),
          ActiveWorkoutState(status: WorkoutStatus.finishing, workout: lower),
        ),
        inProgress('Upper Lower · Lower'),
      );
    });

    test('shows no program day that is not the one it was started from', () {
      final name = inProgress('Upper Lower · Lower');
      // A free workout.
      expect(
        next(
          ready(),
          running(
            Workout(
              id: 'w2',
              startedAt: started,
              name: 'Upper Lower · Lower',
              exercises: const [exercise],
            ),
          ),
        ),
        name,
      );
      // The program is gone, or the day.
      expect(next(ready(programs: const []), running(lower)), name);
      final moved = Workout(
        id: 'w3',
        startedAt: started,
        programId: 'p1',
        dayIndex: 9,
        name: 'Upper Lower · Lower',
        exercises: const [exercise],
      );
      expect(next(ready(), running(moved)), name);
      // Days reordered or renamed since, or the workout renamed.
      final reordered = program(id: 'p1');
      final swapped = Program(
        id: 'p1',
        name: reordered.name,
        days: reordered.days.reversed.toList(),
      );
      expect(next(ready(programs: [swapped]), running(lower)), name);
      expect(
        next(ready(), running(lower.copyWith(name: 'Leg day'))),
        inProgress('Leg day'),
      );
    });

    test('does not count while empty, nor once finished', () {
      final empty = Workout(id: 'w4', startedAt: started, name: 'Workout');
      expect(next(ready(), running(empty)), const NoProgramDay(saved: 1));
      expect(
        next(
          ready(),
          ActiveWorkoutState(status: WorkoutStatus.finished, workout: lower),
        ),
        const NoProgramDay(saved: 1),
      );
    });

    test('is not known while it is looked for, so no Start shows', () {
      expect(
        next(
          ready(activeProgram: active, nextDate: CalendarDate(2026, 11, 12)),
          const ActiveWorkoutState(),
        ),
        isNull,
      );
    });

    test('is at the first exercise with a set not done, counting every '
        'done set', () {
      const done = WorkoutSet(reps: 5, done: true);
      const open = WorkoutSet(reps: 5);
      final progressed = lower.copyWith(
        exercises: [
          exercise.copyWith(sets: const [done, done, done]),
          exercise.copyWith(sets: const [done, open, open]),
          exercise.copyWith(sets: const [open]),
          exercise.copyWith(sets: const [done, done, open]),
        ],
      );
      final at = next(ready(), running(progressed))! as WorkoutInProgress;
      expect((at.exercise, at.exercises, at.doneSets), (2, 4, 6));
      // Every set done: the last exercise.
      final all = lower.copyWith(
        exercises: [
          exercise.copyWith(sets: const [done]),
          exercise.copyWith(sets: const [done]),
        ],
      );
      final allDone = next(ready(), running(all))! as WorkoutInProgress;
      expect(
        (allDone.exercise, allDone.exercises, allDone.doneSets),
        (2, 2, 2),
      );
    });

    test('rebuilds the card only for what it shows', () {
      const set = WorkoutSet(reps: 5);
      final view = activeWorkoutViewOf(
        running(
          lower.copyWith(
            exercises: [
              exercise.copyWith(sets: [set]),
            ],
          ),
        ),
      );
      final edited = lower.copyWith(
        exercises: [
          exercise.copyWith(sets: [set.copyWith(reps: () => 8)]),
        ],
      );
      expect(activeWorkoutViewOf(running(edited)), view);
      final logged = lower.copyWith(
        exercises: [
          exercise.copyWith(sets: [set.copyWith(done: true)]),
        ],
      );
      expect(activeWorkoutViewOf(running(logged)), isNot(view));
    });
  });

  test('nothing is known while the list loads or failed', () {
    expect(idle(const ProgramListState()), isNull);
    expect(
      idle(const ProgramListState(status: ProgramListStatus.failure)),
      isNull,
    );
  });

  test(
    'without an active program there is no program day, the saved ones counted',
    () {
      expect(idle(ready()), const NoProgramDay(saved: 1));
    },
  );

  test('an active program that no longer exists is none', () {
    expect(
      idle(ready(programs: const [], activeProgram: active)),
      const NoProgramDay(),
    );
  });

  test('a finished program is named, with no day to do', () {
    expect(
      idle(ready(activeProgram: active, finished: true)),
      NoProgramDay(finished: upperLower, saved: 1),
    );
  });

  test('the next day comes with its planned date', () {
    expect(
      idle(ready(activeProgram: active, nextDate: CalendarDate(2026, 11, 12))),
      NextProgramDay(
        program: upperLower,
        dayIndex: 1,
        date: CalendarDate(2026, 11, 12),
        access: ProgramAccess.open,
      ),
    );
  });

  test('a missed day is offered to resolve, with where it would move', () {
    expect(
      idle(
        ready(
          activeProgram: active,
          nextDate: CalendarDate(2026, 11, 16),
          missedDay: missed,
          moveDate: CalendarDate(2026, 11, 16),
        ),
      ),
      MissedProgramDay(
        program: upperLower,
        missed: missed,
        moveDate: CalendarDate(2026, 11, 16),
      ),
    );
  });

  group('a next day planned after today', () {
    final monday = CalendarDate(2026, 11, 16);
    final push = Workout(
      id: 'w5',
      startedAt: DateTime(2026, 11, 12, 7),
      finishedAt: DateTime(2026, 11, 12, 8),
      programId: 'p1',
      dayIndex: 0,
      name: 'Upper Lower · Upper',
    );
    final evening = Workout(
      id: 'w6',
      startedAt: DateTime(2026, 11, 12, 19),
      finishedAt: DateTime(2026, 11, 12, 20),
      name: 'Workout',
    );

    test('makes a rest day when nothing was done today', () {
      expect(
        idle(ready(activeProgram: active, nextDate: monday)),
        RestDay(
          program: upperLower,
          dayIndex: 1,
          date: monday,
          access: ProgramAccess.open,
        ),
      );
    });

    test('shows the latest workout finished today', () {
      expect(
        idle(
          ready(activeProgram: active, nextDate: monday),
          done: [push, evening],
        ),
        DoneToday(
          workout: evening,
          program: upperLower,
          dayIndex: 1,
          date: monday,
        ),
      );
    });

    test('is not known while today\'s workouts are', () {
      expect(
        idle(ready(activeProgram: active, nextDate: monday), done: null),
        isNull,
      );
    });

    test('keeps a locked copy locked, Start early opening the paywall', () {
      final next = idle(
        ready(programs: [premiumCopy], activeProgram: active, nextDate: monday),
      );
      expect((next! as RestDay).access, ProgramAccess.locked);
    });

    test('a workout today does not hide a day planned for today', () {
      expect(
        idle(
          ready(activeProgram: active, nextDate: thursday),
          done: [push],
        ),
        NextProgramDay(
          program: upperLower,
          dayIndex: 1,
          date: thursday,
          access: ProgramAccess.open,
        ),
      );
    });
  });

  test('a program ending before another training day shows its next day '
      'undated', () {
    expect(
      idle(ready(activeProgram: active)),
      NextProgramDay(
        program: upperLower,
        dayIndex: 1,
        date: null,
        access: ProgramAccess.open,
      ),
    );
  });

  group('a copy of a premium program', () {
    test('is open with premium', () {
      final next = idle(
        ready(
          programs: [premiumCopy],
          activeProgram: active,
          nextDate: CalendarDate(2026, 11, 12),
          premium: true,
        ),
      );
      expect((next as NextProgramDay).access, ProgramAccess.open);
    });

    test('is locked without premium, its missed day not resolvable', () {
      expect(
        idle(
          ready(
            programs: [premiumCopy],
            activeProgram: active,
            nextDate: CalendarDate(2026, 11, 16),
            missedDay: missed,
            moveDate: CalendarDate(2026, 11, 16),
          ),
        ),
        NextProgramDay(
          program: premiumCopy,
          dayIndex: 1,
          date: CalendarDate(2026, 11, 16),
          access: ProgramAccess.locked,
        ),
      );
    });

    test('is not known while premium is unknown, missed day or not', () {
      expect(
        idle(
          ready(
            programs: [premiumCopy],
            activeProgram: active,
            nextDate: CalendarDate(2026, 11, 12),
            premium: null,
          ),
        ),
        isNull,
      );
      // Not a planned day with Start in place of the missed one.
      expect(
        idle(
          ready(
            programs: [premiumCopy],
            activeProgram: active,
            nextDate: CalendarDate(2026, 11, 16),
            missedDay: missed,
            moveDate: CalendarDate(2026, 11, 16),
            premium: null,
          ),
        ),
        isNull,
      );
    });
  });
}
