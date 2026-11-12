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
    weekdays: const [1, 4],
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

  /// No workout in progress.
  NextWorkout? idle(ProgramListState state) => nextWorkoutOf(
    state,
    const ActiveWorkoutState(status: WorkoutStatus.none),
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
    final dayOne = Workout(
      id: 'w1',
      startedAt: started,
      programId: 'p1',
      dayIndex: 1,
      name: 'Upper Lower · Lower',
      exercises: [exercise],
    );

    test('comes first, with its program day', () {
      expect(
        nextWorkoutOf(
          ready(activeProgram: active, nextDate: CalendarDate(2026, 11, 12)),
          running(dayOne),
        ),
        WorkoutInProgress(workout: dayOne, program: upperLower, dayIndex: 1),
      );
    });

    test('also while finishing, and while the list loads', () {
      expect(
        nextWorkoutOf(
          const ProgramListState(),
          ActiveWorkoutState(status: WorkoutStatus.finishing, workout: dayOne),
        ),
        WorkoutInProgress(workout: dayOne),
      );
    });

    test('of no program, or of one gone or without the day, has none', () {
      final free = Workout(
        id: 'w2',
        startedAt: started,
        name: 'Workout',
        exercises: [exercise],
      );
      expect(
        nextWorkoutOf(ready(), running(free)),
        WorkoutInProgress(workout: free),
      );
      expect(
        nextWorkoutOf(ready(programs: const []), running(dayOne)),
        WorkoutInProgress(workout: dayOne),
      );
      final dayNine = Workout(
        id: 'w3',
        startedAt: started,
        programId: 'p1',
        dayIndex: 9,
        name: 'Upper Lower · Day 10',
        exercises: [exercise],
      );
      expect(
        nextWorkoutOf(ready(), running(dayNine)),
        WorkoutInProgress(workout: dayNine, program: upperLower),
      );
    });

    test('does not count while empty, nor once finished', () {
      final empty = Workout(id: 'w4', startedAt: started, name: 'Workout');
      expect(nextWorkoutOf(ready(), running(empty)), const NoProgramDay());
      expect(
        nextWorkoutOf(
          ready(),
          ActiveWorkoutState(status: WorkoutStatus.finished, workout: dayOne),
        ),
        const NoProgramDay(),
      );
    });
  });

  test('nothing is known while the list loads or failed', () {
    expect(idle(const ProgramListState()), isNull);
    expect(
      idle(const ProgramListState(status: ProgramListStatus.failure)),
      isNull,
    );
  });

  test('without an active program there is no program day', () {
    expect(idle(ready()), const NoProgramDay());
  });

  test('an active program that no longer exists is none', () {
    expect(
      idle(ready(programs: const [], activeProgram: active)),
      const NoProgramDay(),
    );
  });

  test('a finished program is named, with no day to do', () {
    expect(
      idle(ready(activeProgram: active, finished: true)),
      NoProgramDay(finished: upperLower),
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
