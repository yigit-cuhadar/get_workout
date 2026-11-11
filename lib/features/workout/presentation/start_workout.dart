import 'package:flutter/material.dart';
import 'package:forge_core/forge_core.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
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
  final cubit = sl<ActiveWorkoutCubit>();
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
