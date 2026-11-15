import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/program_list_cubit.dart';
import 'active_workout_cubit.dart';
import 'elapsed_text.dart';
import 'rest_timer_cubit.dart';
import 'widgets/workout_bar.dart';
import 'workout_text.dart';

/// The minimized workout, a [WorkoutBar] above the tab bar on every tab
/// while one is in progress or its summary waits, with the time since it
/// started or the rest's time left; tapping it opens the workout. Also
/// tells the user when a workout refused by the server is back in
/// progress, or kept workouts could not be read.
class RunningWorkoutBar extends StatelessWidget {
  const RunningWorkoutBar({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ActiveWorkoutCubit, ActiveWorkoutState>(
        listenWhen: (_, current) =>
            current.restored != null || current.localUnreadable,
        listener: (context, state) {
          final l10n = AppLocalizations.of(context);
          final cubit = context.read<ActiveWorkoutCubit>();
          if (state.restored case final name?) {
            showForgeSnackbar(
              context,
              message: l10n.workoutRestored(name),
              actionLabel: l10n.workoutOpen,
              onAction: () => context.push(Routes.workout),
            );
            cubit.restoredShown();
          }
          if (state.localUnreadable) {
            showForgeSnackbar(context, message: l10n.workoutLocalUnreadable);
            cubit.localUnreadableShown();
          }
        },
        builder: (context, state) {
          final workout = state.workout;
          final shown =
              workout != null &&
              (state.inProgress || state.status == WorkoutStatus.finished);
          if (!shown) return const SizedBox.shrink();
          final l10n = AppLocalizations.of(context);
          Widget bar(String detail) => WorkoutBar(
            name: l10n.workoutShortName(
              workout,
              context.read<ProgramListCubit>().state.programs,
            ),
            detail: detail,
            onTap: () => context.push(Routes.workout),
          );
          if (state.status == WorkoutStatus.finished) {
            return bar(l10n.workoutBarFinished);
          }
          return BlocBuilder<RestTimerCubit, RestTimerState>(
            buildWhen: (previous, current) =>
                previous.phase != current.phase ||
                previous.remainingS != current.remainingS,
            builder: (context, rest) => switch (rest.phase) {
              RestPhase.none => EverySecond(
                builder: (_) => bar(
                  l10n.elapsedText(
                    DateTime.now().difference(workout.startedAt),
                  ),
                ),
              ),
              RestPhase.running => bar(
                l10n.restRemaining(
                  l10n.elapsedText(Duration(seconds: rest.remainingS)),
                ),
              ),
              RestPhase.over => bar(l10n.restOver),
            },
          );
        },
      );
}
