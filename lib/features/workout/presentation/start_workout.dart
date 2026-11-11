import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/text_length.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
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
  Future<WorkoutStart> Function(ActiveWorkoutCubit cubit) start,
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
  final result = await start(cubit);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!result.started) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.workoutStartFailed)));
    return;
  }
  if (result.skipped > 0) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.workoutSkippedExercises(result.skipped))),
    );
  }
  await context.push(Routes.workout);
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
  return startWorkout(
    context,
    (cubit) async => (started: cubit.startFree(name), skipped: 0),
  );
}

/// Adds [exercise] to the workout in progress, or, after asking, starts a
/// workout with it.
Future<void> addToWorkout(BuildContext context, Exercise exercise) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<ActiveWorkoutCubit>();
  final language = Localizations.localeOf(context).languageCode;
  final name = exercise.localized(context).name;
  final workout = cubit.state.workout;
  if (cubit.state.status == WorkoutStatus.active && workout != null) {
    final added = cubit.addExercises([exercise], language);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? l10n.workoutAdded(name, workout.name) : l10n.workoutAddFailed,
        ),
        action: added
            ? SnackBarAction(
                label: l10n.workoutOpen,
                onPressed: () => context.push(Routes.workout),
              )
            : null,
      ),
    );
    return;
  }
  final start = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.workoutStartWithTitle),
      content: Text(l10n.workoutStartWithBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.workoutStartWorkout),
        ),
      ],
    ),
  );
  if (start != true || !context.mounted) return;
  await startWorkout(
    context,
    (cubit) async => (
      started: cubit.startWith(exercise, l10n.workoutFreeName, language),
      skipped: 0,
    ),
  );
}
