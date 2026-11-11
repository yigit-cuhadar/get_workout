import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../domain/workout.dart';
import 'active_workout_cubit.dart';

enum _InProgressChoice { resume, discard }

/// Starts a workout with [start] and opens it. While another is in progress
/// the user resumes that one or discards it first; a finished one whose
/// summary is still open is put away.
Future<void> startWorkout(
  BuildContext context,
  bool Function(ActiveWorkoutCubit cubit) start,
) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<ActiveWorkoutCubit>();
  final current = cubit.state.workout;
  if (cubit.state.inProgress && current != null) {
    final choice = await showDialog<_InProgressChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.workoutInProgressTitle),
        content: Text(l10n.workoutInProgressBody(current.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _InProgressChoice.discard),
            child: Text(l10n.workoutDiscardAndStart),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _InProgressChoice.resume),
            child: Text(l10n.workoutResume),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == _InProgressChoice.resume) {
      await context.push(Routes.workout);
      return;
    }
    await cubit.discard();
  }
  cubit.summaryShown();
  if (!context.mounted) return;
  if (start(cubit)) {
    await context.push(Routes.workout);
  } else {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.workoutStartFailed)));
  }
}

/// Starts day [dayIndex] of [program]; see [startWorkout].
Future<void> startProgramDay(
  BuildContext context,
  Program program,
  int dayIndex,
) {
  final l10n = AppLocalizations.of(context);
  final language = Localizations.localeOf(context).languageCode;
  final name = l10n.workoutProgramDayName(
    program.name,
    l10n.dayName(program.days[dayIndex], dayIndex),
  );
  return startWorkout(
    context,
    (cubit) => cubit.startProgramDay(
      program,
      dayIndex,
      name: cutToLength(name, WorkoutLimits.maxNameLength),
      language: language,
    ),
  );
}

/// Starts an empty workout; see [startWorkout].
Future<void> startFreeWorkout(BuildContext context) {
  final name = AppLocalizations.of(context).workoutFreeName;
  return startWorkout(context, (cubit) => cubit.startFree(name));
}
