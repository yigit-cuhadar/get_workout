import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/effort.dart';
import 'workout_text.dart';

/// A "?" opening [WorkoutHelpSheet]. Needs [SettingsCubit] above it.
class WorkoutHelpButton extends StatelessWidget {
  const WorkoutHelpButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).workoutHelp,
    icon: const Icon(Icons.help_outline),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const WorkoutHelpSheet(),
    ),
  );
}

/// What effort is and each step of the user's scale means, what failed
/// means, and what warm-up and drop sets are; one sheet that scrolls.
class WorkoutHelpSheet extends StatelessWidget {
  const WorkoutHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = context.select(
      (SettingsCubit cubit) => cubit.state.settings.effortScale,
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xs),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return DraggableScrollableSheet(
      expand: false,
      builder: (context, controller) => SafeArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          children: [
            Text(l10n.helpTitle, style: theme.textTheme.titleLarge),
            heading(l10n.helpEffortTitle),
            Text(l10n.helpEffortBody),
            const SizedBox(height: Gap.sm),
            Text(switch (scale) {
              EffortScale.byFeel => l10n.helpScaleFeel,
              EffortScale.rir => l10n.helpScaleRir,
              EffortScale.rpe => l10n.helpScaleRpe,
            }),
            for (final step in scale.steps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.effortStepLabel(step, scale)),
                subtitle: Text(l10n.effortStepMeaning(step, scale)),
              ),
            Text(l10n.helpSettingsHint, style: theme.textTheme.bodySmall),
            heading(l10n.helpWarmupTitle),
            Text(l10n.helpWarmupBody),
            heading(l10n.helpDropTitle),
            Text(l10n.helpDropBody),
          ],
        ),
      ),
    );
  }
}

/// A first-use tip in the flow of the page, never in the way: [text] and
/// a button that dismisses it.
class TipBanner extends StatelessWidget {
  const TipBanner({super.key, required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    leading: const Icon(Icons.lightbulb_outline),
    content: Text(text),
    actions: [
      TextButton(
        onPressed: onDismiss,
        child: Text(AppLocalizations.of(context).tipDismiss),
      ),
    ],
  );
}
