import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/today/presentation/next_workout.dart';

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

  test('without an active program there is no program day', () {
    expect(nextWorkoutOf(ready()), const NoProgramDay());
  });

  test('an active program that no longer exists is none', () {
    expect(
      nextWorkoutOf(ready(programs: const [], activeProgram: active)),
      const NoProgramDay(),
    );
  });

  test('a finished program is named, with no day to do', () {
    expect(
      nextWorkoutOf(ready(activeProgram: active, finished: true)),
      NoProgramDay(finished: upperLower),
    );
  });

  test('the next day comes with its planned date', () {
    expect(
      nextWorkoutOf(
        ready(activeProgram: active, nextDate: CalendarDate(2026, 11, 12)),
      ),
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
      nextWorkoutOf(
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
      final next = nextWorkoutOf(
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
        nextWorkoutOf(
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

    test('waits while premium is unknown', () {
      final next = nextWorkoutOf(
        ready(
          programs: [premiumCopy],
          activeProgram: active,
          nextDate: CalendarDate(2026, 11, 12),
          premium: null,
        ),
      );
      expect((next as NextProgramDay).access, ProgramAccess.waiting);
    });
  });
}
