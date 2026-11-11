import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'active_workout_cubit.dart';
import 'elapsed_text.dart';

/// The minimized workout, above the tab bar on every tab while one is in
/// progress or its summary waits; tapping it opens the workout. Also tells
/// the user when a workout refused by the server is back in progress, or
/// kept workouts could not be read.
class WorkoutBar extends StatelessWidget {
  const WorkoutBar({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ActiveWorkoutCubit, ActiveWorkoutState>(
        listenWhen: (_, current) =>
            current.restored != null || current.localUnreadable,
        listener: (context, state) {
          final l10n = AppLocalizations.of(context);
          final cubit = context.read<ActiveWorkoutCubit>();
          final messenger = ScaffoldMessenger.of(context);
          if (state.restored case final name?) {
            messenger.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 10),
                content: Text(l10n.workoutRestored(name)),
                action: SnackBarAction(
                  label: l10n.workoutOpen,
                  onPressed: () => context.push(Routes.workout),
                ),
              ),
            );
            cubit.restoredShown();
          }
          if (state.localUnreadable) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.workoutLocalUnreadable)),
            );
            cubit.localUnreadableShown();
          }
        },
        builder: (context, state) {
          final workout = state.workout;
          final shown =
              workout != null &&
              (state.inProgress || state.status == WorkoutStatus.finished);
          if (!shown) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return Material(
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.fitness_center),
              title: Text(workout.name, maxLines: 1),
              subtitle: state.status == WorkoutStatus.finished
                  ? Text(AppLocalizations.of(context).workoutBarFinished)
                  : ElapsedText(since: workout.startedAt),
              trailing: const Icon(Icons.keyboard_arrow_up),
              onTap: () => context.push(Routes.workout),
            ),
          );
        },
      );
}
