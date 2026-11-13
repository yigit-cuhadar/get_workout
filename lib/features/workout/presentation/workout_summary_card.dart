import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/exercise_stats.dart';
import 'workout_text.dart';

/// The prominent card of a workout's [summary], shared by the summary after
/// finishing and a stored workout's page: a [caption] (what happened, or
/// when), the [program] it came from, its [title] and the four totals.
class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({
    super.key,
    required this.summary,
    required this.caption,
    this.title,
    this.program,
  });

  final WorkoutSummary summary;
  final String caption;
  final String? title;
  final Widget? program;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = colors.onPrimaryContainer;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final title = this.title;
    final program = this.program;
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        iconTheme: theme.iconTheme.copyWith(color: foreground),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Builder(
            builder: (context) {
              final text = Theme.of(context).textTheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(caption, style: text.titleSmall),
                      ?program,
                    ],
                  ),
                  if (title != null) ...[
                    const SizedBox(height: Gap.xs),
                    Text(title, style: text.headlineSmall),
                  ],
                  const SizedBox(height: Gap.md),
                  _StatRow(
                    first: (
                      l10n.workoutDuration,
                      l10n.durationMinutes(summary.duration),
                    ),
                    second: (
                      l10n.workoutVolume,
                      l10n.weightText(summary.volumeKg, unit),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  _StatRow(
                    first: (l10n.workoutSets, '${summary.setCount}'),
                    second: (l10n.workoutExercises, '${summary.exerciseCount}'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Two totals side by side, each a label over its value.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.first, required this.second});

  final (String, String) first;
  final (String, String) second;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget stat((String, String) stat) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.$1, style: text.bodySmall),
          Text(stat.$2, style: text.titleLarge),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stat(first),
        const SizedBox(width: Gap.sm),
        stat(second),
      ],
    );
  }
}
