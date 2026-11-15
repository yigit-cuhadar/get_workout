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

/// The active [program]'s next day, [dayIndex], is planned for the later
/// [date] and nothing was trained today: a rest day, from which that day
/// can still start early (through the paywall when [access] is locked).
class RestDay extends NextWorkout {
  const RestDay({
    required this.program,
    required this.dayIndex,
    required this.date,
    required this.access,
  });

  final Program program;
  final int dayIndex;
  final CalendarDate date;
  final ProgramAccess access;

  @override
  List<Object?> get props => [program, dayIndex, date, access];
}

/// [workout] was finished today and the active [program]'s next day,
/// [dayIndex], is planned for the later [date].
class DoneToday extends NextWorkout {
  const DoneToday({
    required this.workout,
    required this.program,
    required this.dayIndex,
    required this.date,
  });

  final Workout workout;
  final Program program;
  final int dayIndex;
  final CalendarDate date;

  @override
  List<Object?> get props => [workout, program, dayIndex, date];
}

/// The active [program]'s next day was [missed]; it is resolved as in the
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

/// A workout named [name] is in progress since [startedAt], so it is
/// resumed rather than another started; started from day [dayIndex] of
/// [program] when that day is still the one it was started from. It is at
/// exercise [exercise] (from 1, the first with a set not done) of
/// [exercises], with [doneSets] sets done in all.
class WorkoutInProgress extends NextWorkout {
  const WorkoutInProgress({
    required this.name,
    required this.startedAt,
    required this.exercise,
    required this.exercises,
    required this.doneSets,
    this.program,
    this.dayIndex,
  });

  final String name;
  final DateTime startedAt;
  final int exercise;
  final int exercises;
  final int doneSets;
  final Program? program;
  final int? dayIndex;

  @override
  List<Object?> get props => [
    name,
    startedAt,
    exercise,
    exercises,
    doneSets,
    program,
    dayIndex,
  ];
}

/// What Today shows of the active workout, so the card rebuilds only when
/// that changes, not on every logged set.
typedef ActiveWorkoutView = ({
  bool loading,
  bool inProgress,
  String? name,
  String? programId,
  int? dayIndex,
  DateTime? startedAt,
  int exercise,
  int exercises,
  int doneSets,
});

ActiveWorkoutView activeWorkoutViewOf(ActiveWorkoutState state) {
  final exercises = state.workout?.exercises ?? const [];
  final open = exercises.indexWhere((e) => e.sets.any((s) => !s.done));
  return (
    loading: state.status == WorkoutStatus.loading,
    inProgress: state.inProgress,
    name: state.workout?.name,
    programId: state.workout?.programId,
    dayIndex: state.workout?.dayIndex,
    startedAt: state.workout?.startedAt,
    // Every set done: the last one.
    exercise: open == -1 ? exercises.length : open + 1,
    exercises: exercises.length,
    doneSets: state.workout?.doneSetCount ?? 0,
  );
}

/// What Today knows of [today]: the workouts finished on it, oldest first;
/// null while they are not known yet.
typedef TodayView = ({CalendarDate today, List<Workout>? done});

/// The next workout: the one in progress in [active] (an empty one is not),
/// else derived from what the Programs tab shows in [state] and what was
/// done [today]; null until it is known: while the workout in progress is
/// looked for (Start could otherwise show for a day already running),
/// while the list loads, while the premium status of a premium copy is (a
/// missed day could otherwise show as a planned one with Start), and,
/// before a later next day, while today's workouts are. A missed day is
/// offered only while the program is open, as there. A next day planned
/// after today, none missed, makes today a rest day, or done when a workout
/// was finished today (the latest).
///
/// A workout does not store its day's name; [startName] is the name a day
/// gives the workout it starts, so a workout still named so was started
/// from that day as it is now (not since renamed, moved or deleted).
NextWorkout? nextWorkoutOf(
  ProgramListState state,
  ActiveWorkoutView active, {
  required String Function(Program program, int dayIndex) startName,
  required TodayView today,
}) {
  if (active.loading) return null;
  if (active case (
    inProgress: true,
    name: final name?,
    startedAt: final startedAt?,
    :final programId,
    :final dayIndex,
    loading: _,
    exercise: _,
    exercises: _,
    doneSets: _,
  )) {
    final program = programId == null ? null : state.program(programId);
    final matches =
        program != null &&
        dayIndex != null &&
        dayIndex < program.days.length &&
        startName(program, dayIndex) == name;
    return WorkoutInProgress(
      name: name,
      startedAt: startedAt,
      exercise: active.exercise,
      exercises: active.exercises,
      doneSets: active.doneSets,
      program: matches ? program : null,
      dayIndex: matches ? dayIndex : null,
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
  final date = state.nextDate;
  // A locked copy's missed day stays due, as its block.
  if (date != null && missed == null && date.isAfter(today.today)) {
    final done = today.done;
    if (done == null) return null;
    if (done.lastOrNull case final workout?) {
      return DoneToday(
        workout: workout,
        program: program,
        dayIndex: dayIndex,
        date: date,
      );
    }
    return RestDay(
      program: program,
      dayIndex: dayIndex,
      date: date,
      access: access,
    );
  }
  return NextProgramDay(
    program: program,
    dayIndex: dayIndex,
    date: date,
    access: access,
  );
}
