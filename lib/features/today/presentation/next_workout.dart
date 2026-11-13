import 'package:forge_core/forge_core.dart';

import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/presentation/program_list_cubit.dart';
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

/// The active [program]'s next day was [missed]; it is resolved as in
/// Train's "My program", or started anyway.
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

/// A workout named [name] is in progress, so it is resumed rather than
/// another started; started from day [dayIndex] of [program] when that
/// day is still the one it was started from.
class WorkoutInProgress extends NextWorkout {
  const WorkoutInProgress({required this.name, this.program, this.dayIndex});

  final String name;
  final Program? program;
  final int? dayIndex;

  @override
  List<Object?> get props => [name, program, dayIndex];
}

/// What Today shows of the active workout, so the card rebuilds only when
/// that changes, not on every logged set.
typedef ActiveWorkoutView = ({
  bool loading,
  bool inProgress,
  String? name,
  String? programId,
  int? dayIndex,
});

ActiveWorkoutView activeWorkoutViewOf(ActiveWorkoutState state) => (
  loading: state.status == WorkoutStatus.loading,
  inProgress: state.inProgress,
  name: state.workout?.name,
  programId: state.workout?.programId,
  dayIndex: state.workout?.dayIndex,
);

/// The next workout: the one in progress in [active] (an empty one is not),
/// else derived only from what "My program" shows in [state]; null
/// until it is known: while the workout in progress is looked for (Start
/// could otherwise show for a day already running), while the list loads,
/// and while the premium status of a premium copy is (a missed day could
/// otherwise show as a planned one with Start). A missed day is offered
/// only while the program is open, as there.
///
/// A workout does not store its day's name; [startName] is the name a day
/// gives the workout it starts, so a workout still named so was started
/// from that day as it is now (not since renamed, moved or deleted).
NextWorkout? nextWorkoutOf(
  ProgramListState state,
  ActiveWorkoutView active, {
  required String Function(Program program, int dayIndex) startName,
}) {
  if (active.loading) return null;
  if (active case (
    inProgress: true,
    name: final name?,
    :final programId,
    :final dayIndex,
    loading: _,
  )) {
    final program = programId == null ? null : state.program(programId);
    final matches =
        program != null &&
        dayIndex != null &&
        dayIndex < program.days.length &&
        startName(program, dayIndex) == name;
    return matches
        ? WorkoutInProgress(name: name, program: program, dayIndex: dayIndex)
        : WorkoutInProgress(name: name);
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
