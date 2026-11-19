import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/text_length.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/workout.dart';
import 'active_workout_cubit.dart';
import 'rest_timer_cubit.dart';

enum _InProgressChoice { resume, discard }

/// Starts a workout with [start] and opens it. While another is in progress
/// the user resumes that one or discards it first; an empty one is simply
/// replaced, and a finished one whose summary is still open is put away.
Future<void> startWorkout(
  BuildContext context,
  Future<WorkoutStart> Function(ActiveWorkoutCubit cubit) start,
) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<ActiveWorkoutCubit>();
  final current = cubit.state.workout;
  if (cubit.state.inProgress && current != null) {
    final choice = await showForgeDialog<_InProgressChoice>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.workoutInProgressTitle,
        message: l10n.workoutInProgressBody(current.name),
        action: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            ForgeButton(
              label: l10n.workoutResume,
              onPressed: () => Navigator.pop(context, _InProgressChoice.resume),
            ),
            ForgeButton(
              label: l10n.workoutDiscardAndStart,
              onPressed: () =>
                  Navigator.pop(context, _InProgressChoice.discard),
              variant: ForgeButtonVariant.danger,
            ),
          ],
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          onPressed: () => Navigator.pop(context),
          variant: ForgeButtonVariant.secondary,
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == _InProgressChoice.resume) {
      await context.push(Routes.workout);
      return;
    }
    await cubit.discard();
    if (!context.mounted) return;
  }
  await _askNotify(context);
  if (!context.mounted) return;
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

/// Before the first workout on this device, whether to notify when a rest
/// is over, as a permission dialog: asked here rather than mid-set, where
/// the system's own question that a yes brings would cover the workout.
Future<void> _askNotify(BuildContext context) async {
  final timer = context.read<RestTimerCubit>();
  if (!await timer.shouldAskNotify() || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final allow = await showForgeDialog<bool>(
    context: context,
    builder: (context) => PermissionPrompt.dialog(
      icon: ForgeIcons.notifications,
      title: l10n.restNotifyQuestion,
      message: l10n.restNotifyBody,
      allowLabel: l10n.restNotifyAllow,
      onAllow: () => Navigator.pop(context, true),
      notNowLabel: l10n.restNotifyLater,
      onNotNow: () => Navigator.pop(context, false),
    ),
  );
  // Closed without an answer is a "Not now".
  await timer.answerNotify(allow: allow ?? false);
}

/// Starts day [dayIndex] of [program]; see [startWorkout]. A copy of a
/// premium program needs premium: without it the paywall opens instead, and
/// the day starts only if the user unlocked it there.
Future<void> startProgramDay(
  BuildContext context,
  Program program,
  int dayIndex,
) async {
  final access = context.read<ActiveWorkoutCubit>().access(program);
  if (access != ProgramAccess.open && !await context.requirePremium()) return;
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final language = Localizations.localeOf(context).languageCode;
  final name = l10n.workoutProgramDayName(
    program.name,
    l10n.dayName(program.days[dayIndex], dayIndex),
  );
  await startWorkout(
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
  if (cubit.state.inProgress && workout != null) {
    final added = cubit.addExercises([exercise], language);
    showForgeSnackbar(
      context,
      message: added
          ? l10n.workoutAdded(name, workout.name)
          : l10n.workoutAddFailed,
      actionLabel: added ? l10n.workoutOpen : null,
      onAction: added ? () => context.push(Routes.workout) : null,
      error: !added,
    );
    return;
  }
  final start = await showForgeDialog<bool>(
    context: context,
    builder: (context) => ForgeDialog(
      title: l10n.workoutStartWithTitle,
      message: l10n.workoutStartWithBody(name),
      action: ForgeButton(
        label: l10n.workoutStartWorkout,
        onPressed: () => Navigator.pop(context, true),
      ),
      cancel: ForgeButton(
        label: l10n.cancel,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context, false),
      ),
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
