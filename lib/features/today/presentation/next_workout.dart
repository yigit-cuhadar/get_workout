import 'package:forge_core/forge_core.dart';

import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../workout/domain/workout.dart';
import '../../workout/presentation/active_workout_cubit.dart';

/// What the Today tab offers to train next.
sealed class NextWorkout extends Equatable {
  const NextWorkout();
}

/// No program day to do: no active program (or it no longer exists or has
/// no days), or it ran its length, then [finished].
class NoProgramDay extends NextWorkout {
  const NoProgramDay({this.finished});
  final Program? finished;

  @override
  List<Object?> get props => [finished];
}

/// The active [program]'s next day, planned for [date] (null when the
/// program ends before another training day). Locked, starting it opens
/// the paywall.
class NextProgramDay extends NextWorkout {
  const NextProgramDay({
    required this.program,
    required this.dayIndex,
    required this.date,
    required this.access,
  });

  final Program program;
  final int dayIndex;
  final CalendarDate? date;
  final ProgramAccess access;

  @override
  List<Object?> get props => [program, dayIndex, date, access];
}

/// The active [program]'s next day was [missed]; it is resolved as on the
/// Programs tab, or started anyway.
class MissedProgramDay extends NextWorkout {
  const MissedProgramDay({
    required this.program,
    required this.missed,
    required this.moveDate,
  });

  final Program program;
  final PlannedDay missed;

  /// Where moving it would put it.
  final CalendarDate moveDate;

  @override
  List<Object?> get props => [program, missed, moveDate];
}

/// A [workout] is in progress, so it is resumed rather than another
/// started; started from day [dayIndex] of [program] when that program
/// is known and still has the day.
class WorkoutInProgress extends NextWorkout {
  const WorkoutInProgress({required this.workout, this.program, this.dayIndex});

  final Workout workout;
  final Program? program;
  final int? dayIndex;

  @override
  List<Object?> get props => [workout, program, dayIndex];
}

/// The next workout: the one in progress in [active] (an empty one is not),
/// else derived only from what the Programs tab shows in [state]; null
/// until it is known: while the list loads, and while the premium status
/// of a premium copy is (a missed day could otherwise show as a planned
/// one with Start). A missed day is offered only while the program is
/// open, as there.
NextWorkout? nextWorkoutOf(ProgramListState state, ActiveWorkoutState active) {
  if (active.workout case final workout? when active.inProgress) {
    final program = switch (workout.programId) {
      final id? => state.program(id),
      null => null,
    };
    final dayIndex = workout.dayIndex;
    final hasDay =
        program != null && dayIndex != null && dayIndex < program.days.length;
    return WorkoutInProgress(
      workout: workout,
      program: program,
      dayIndex: hasDay ? dayIndex : null,
    );
  }
  if (state.status != ProgramListStatus.ready) return null;
  final program = state.activeProgram;
  final dayIndex = state.nextDayIndex;
  if (program == null || dayIndex == null) {
    return NoProgramDay(finished: state.finished ? program : null);
  }
  final access = state.access(program);
  if (access == ProgramAccess.waiting) return null;
  final missed = state.missed;
  final moveDate = state.moveDate;
  if (missed != null && moveDate != null && access == ProgramAccess.open) {
    return MissedProgramDay(
      program: program,
      missed: missed,
      moveDate: moveDate,
    );
  }
  return NextProgramDay(
    program: program,
    dayIndex: dayIndex,
    date: state.nextDate,
    access: access,
  );
}
