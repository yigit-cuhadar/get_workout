import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/effort.dart';
import '../domain/rest.dart';
import '../domain/set_selection.dart';
import '../domain/workout_tips.dart';
import 'active_workout_cubit.dart';
import 'rest_timer_cubit.dart';
import 'set_bar.dart';
import 'workout_editor.dart';
import 'workout_help.dart';
import 'workout_text.dart';

/// The running rest below the workout, with +15 s and Skip and, while it
/// is the rest of a working set just ticked, the effort question about that
/// set ([_RestQuestion]); then briefly "Rest over"; nothing otherwise. Asks
/// once whether to notify when a rest is over. Only this rebuilds as the
/// seconds pass.
class RestStrip extends StatelessWidget {
  const RestStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return BlocConsumer<RestTimerCubit, RestTimerState>(
      listenWhen: (previous, current) =>
          current.askNotify && !previous.askNotify,
      listener: (context, _) => _askNotify(context),
      buildWhen: (previous, current) =>
          previous.phase != current.phase ||
          previous.remainingS != current.remainingS,
      builder: (context, state) {
        final workout = context.read<ActiveWorkoutCubit>();
        final tile = switch (state.phase) {
          RestPhase.none => null,
          RestPhase.running => ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(
              l10n.restRemaining(
                l10n.elapsedText(Duration(seconds: state.remainingS)),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: workout.extendRest,
                  child: Text(l10n.restAdd(restExtension.inSeconds)),
                ),
                TextButton(
                  onPressed: workout.skipRest,
                  child: Text(l10n.restSkip),
                ),
              ],
            ),
          ),
          RestPhase.over => ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: Text(l10n.restOver),
          ),
        };
        if (tile == null) return const SizedBox.shrink();
        return Material(
          color: colors.secondaryContainer,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                // The countdown always shows; the question scrolls in what
                // the strip's share of the page leaves.
                if (state.phase == RestPhase.running)
                  const Flexible(
                    child: SingleChildScrollView(child: _RestQuestion()),
                  ),
              ],
            ),
          ),
        );
      },
    );
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

/// The effort question about the working set whose rest runs (see
/// [restQuestionSet]): the set and its values with the question, the
/// help, the steps, and the first time its tip; nothing once answered or
/// while edits are refused.
class _RestQuestion extends StatelessWidget {
  const _RestQuestion();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsState = context.select((SettingsCubit cubit) => cubit.state);
    final settings = settingsState.settings;
    final settingsCubit = context.read<SettingsCubit>();
    return BlocBuilder<ActiveWorkoutCubit, ActiveWorkoutState>(
      builder: (context, state) {
        final cubit = context.read<ActiveWorkoutCubit>();
        final asked = cubit.restQuestionRef;
        if (asked == null || !cubit.canEdit) return const SizedBox.shrink();
        final workout = state.workout!;
        final scale = settings.effortScale;
        final set = workout.exercises[asked.exercise].sets[asked.set];
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.xs, Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.effortStripQuestion(
                        scale,
                        workout,
                        asked,
                        state.selection,
                        settings.weightUnit,
                      ),
                      style: Theme.of(context).textTheme.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const WorkoutHelpButton(),
                ],
              ),
              EffortChoice(
                scale: scale,
                chosen: scale.stepOf(set),
                onChosen: (step) {
                  cubit.setEffort(asked, step);
                  // Used, so its tip has nothing left to tell.
                  settingsCubit.tipSeen(Tip.effort);
                },
              ),
              // Below the steps, so it never pushes them or the countdown
              // out of view.
              if (effortTipDue(settingsState.loaded ? settings.seenTips : null))
                TipBanner(
                  text: l10n.tipEffort,
                  onDismiss: () => settingsCubit.tipSeen(Tip.effort),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The rest's time left, or "Rest over", for the minimized workout; [idle]
/// when no rest runs.
class RestOrElse extends StatelessWidget {
  const RestOrElse({super.key, required this.idle});

  final Widget idle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<RestTimerCubit, RestTimerState>(
      buildWhen: (previous, current) =>
          previous.phase != current.phase ||
          previous.remainingS != current.remainingS,
      builder: (context, state) => switch (state.phase) {
        RestPhase.none => idle,
        RestPhase.running => Text(
          l10n.restRemaining(
            l10n.elapsedText(Duration(seconds: state.remainingS)),
          ),
        ),
        RestPhase.over => Text(l10n.restOver),
      },
    );
  }
}
