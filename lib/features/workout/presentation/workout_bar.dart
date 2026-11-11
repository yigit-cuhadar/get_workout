import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'active_workout_cubit.dart';
import 'elapsed_text.dart';

/// The minimized workout, above the tab bar on every tab while one is in
/// progress or its summary waits; tapping it opens the workout. Also tells
/// the user when the server refused a stored workout.
class WorkoutBar extends StatelessWidget {
  const WorkoutBar({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ActiveWorkoutCubit, ActiveWorkoutState>(
        listenWhen: (_, current) => current.writeRejected,
        listener: (context, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).workoutWritesRejected),
            ),
          );
          context.read<ActiveWorkoutCubit>().rejectionShown();
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
