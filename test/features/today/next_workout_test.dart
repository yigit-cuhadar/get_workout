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

  /// The name a day gives the workout it starts, as on the page.
  String startName(Program program, int dayIndex) =>
      '${program.name} · ${program.days[dayIndex].name}';

  NextWorkout? next(ProgramListState state, ActiveWorkoutState workout) =>
      nextWorkoutOf(state, activeWorkoutViewOf(workout), startName: startName);

  /// No workout in progress.
  NextWorkout? idle(ProgramListState state) =>
      next(state, const ActiveWorkoutState(status: WorkoutStatus.none));

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

    test('comes first, with the program day it was started from', () {
      expect(
        next(
          ready(activeProgram: active, nextDate: CalendarDate(2026, 11, 12)),
          running(lower),
        ),
        WorkoutInProgress(
          name: 'Upper Lower · Lower',
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
        const WorkoutInProgress(name: 'Upper Lower · Lower'),
      );
    });

    test('shows no program day that is not the one it was started from', () {
      const name = WorkoutInProgress(name: 'Upper Lower · Lower');
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
        const WorkoutInProgress(name: 'Leg day'),
      );
    });

    test('does not count while empty, nor once finished', () {
      final empty = Workout(id: 'w4', startedAt: started, name: 'Workout');
      expect(next(ready(), running(empty)), const NoProgramDay());
      expect(
        next(
          ready(),
          ActiveWorkoutState(status: WorkoutStatus.finished, workout: lower),
        ),
        const NoProgramDay(),
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

    test('rebuilds the card only for what it shows', () {
      final view = activeWorkoutViewOf(running(lower));
      final logged = lower.copyWith(exercises: const [exercise, exercise]);
      expect(activeWorkoutViewOf(running(logged)), view);
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
