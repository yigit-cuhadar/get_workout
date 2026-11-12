import 'package:forge_core/forge_core.dart';

import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/presentation/program_list_cubit.dart';

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
/// program ends before another training day). With [access] other than
/// open, starting it goes through the premium gate.
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

/// The next workout of a ready [state], derived only from what the
/// Programs tab shows: a missed day is offered only while the program is
/// open, as there.
NextWorkout nextWorkoutOf(ProgramListState state) {
  final program = state.activeProgram;
  final dayIndex = state.nextDayIndex;
  if (program == null || dayIndex == null) {
    return NoProgramDay(finished: state.finished ? program : null);
  }
  final access = state.access(program);
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
