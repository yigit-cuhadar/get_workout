import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/rest.dart';
import 'active_workout_cubit.dart';
import 'rest_timer_cubit.dart';
import 'workout_text.dart';

/// The running rest below the workout, in one slim line: the time left,
/// +15 s and Skip rest; then briefly "Rest over"; nothing otherwise. The
/// effort question about the set just ticked is the set bar's, above it.
/// Asks once whether to notify when a rest is over. Only this rebuilds as
/// the seconds pass.
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
        final line = switch (state.phase) {
          RestPhase.none => null,
          RestPhase.running => Row(
            children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  l10n.restRemaining(
                    l10n.elapsedText(Duration(seconds: state.remainingS)),
                  ),
                ),
              ),
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
          RestPhase.over => Row(
            children: [
              const Icon(Icons.timer_off_outlined),
              const SizedBox(width: Gap.sm),
              Expanded(child: Text(l10n.restOver)),
            ],
          ),
        };
        if (line == null) return const SizedBox.shrink();
        return Material(
          color: colors.secondaryContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.md,
                Gap.xs,
                Gap.xs,
                Gap.xs,
              ),
              child: line,
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
