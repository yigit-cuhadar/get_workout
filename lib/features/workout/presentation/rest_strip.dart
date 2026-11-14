import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/rest.dart';
import 'active_workout_cubit.dart';
import 'rest_timer_cubit.dart';
import 'widgets/rest_panel.dart';
import 'workout_editor.dart';
import 'workout_text.dart';

/// The running rest at the bottom of the workout as a [RestPanel]: the
/// time left, the set that comes next, +15 s and Skip rest; then briefly
/// "Rest over"; nothing otherwise, nor while the effort question about
/// the set just ticked shows (it carries the rest's line itself). Asks
/// once whether to notify when a rest is over. Only this rebuilds as the
/// seconds pass.
class RestStrip extends StatelessWidget {
  const RestStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asking = context.select(
      (ActiveWorkoutCubit cubit) =>
          cubit.state.questionRef != null && cubit.canEdit,
    );
    return BlocConsumer<RestTimerCubit, RestTimerState>(
      listenWhen: (previous, current) =>
          current.askNotify && !previous.askNotify,
      listener: (context, _) => _askNotify(context),
      buildWhen: (previous, current) =>
          previous.phase != current.phase ||
          previous.remainingS != current.remainingS ||
          previous.totalS != current.totalS,
      builder: (context, state) {
        if (asking || state.phase == RestPhase.none) {
          return const SizedBox.shrink();
        }
        final workout = context.read<ActiveWorkoutCubit>();
        final next = _next(l10n, workout.state);
        // What does not fit the rest's share of the page scrolls.
        return SingleChildScrollView(
          child: state.phase == RestPhase.over
              ? RestPanel.over(
                  time: l10n.elapsedText(Duration.zero),
                  next: next,
                )
              : RestPanel(
                  time: l10n.elapsedText(Duration(seconds: state.remainingS)),
                  progress: state.progress,
                  next: next,
                  onAddTime: workout.extendRest,
                  onSkip: workout.skipRest,
                ),
        );
      },
    );
  }

  /// The set to do after the rest, e.g. "Next: Bench Press · set 4 of 4",
  /// or that none is left.
  static String _next(AppLocalizations l10n, ActiveWorkoutState state) {
    final workout = state.workout;
    final next = workout == null ? null : nextSet(workout, state.rest?.after);
    if (workout == null || next == null) return l10n.restPanelAllSetsDone;
    return l10n.restNextText(workout.exercises[next.exercise], next.set);
  }

  Future<void> _askNotify(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<RestTimerCubit>();
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Text(l10n.restNotifyQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.restNotifyLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.restNotifyAllow),
          ),
        ],
      ),
    );
    await cubit.answerNotify(allow: allow ?? false);
  }
}
