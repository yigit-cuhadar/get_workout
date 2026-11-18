import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/effort.dart';
import 'workout_text.dart';

/// Opens [WorkoutHelpSheet]; done once it is closed.
Future<void> openWorkoutHelp(BuildContext context) =>
    showForgeBottomSheet<void>(
      context: context,
      builder: (_) => const WorkoutHelpSheet(),
    );

/// What effort is and each step of the user's scale means, what failed
/// means, and what warm-up and drop sets are; one sheet that scrolls.
class WorkoutHelpSheet extends StatelessWidget {
  const WorkoutHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final scale = context.select(
      (SettingsCubit cubit) => cubit.state.settings.effortScale,
    );
    return ForgeBottomSheet(
      title: l10n.helpTitle,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            SectionLabel(l10n.helpEffortTitle),
            Text(l10n.helpEffortBody),
            Text(switch (scale) {
              EffortScale.byFeel => l10n.helpScaleFeel,
              EffortScale.rir => l10n.helpScaleRir,
              EffortScale.rpe => l10n.helpScaleRpe,
            }),
            for (final step in scale.steps)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.effortStepLabel(step, scale),
                    style: text.titleSmall,
                  ),
                  Text(
                    l10n.effortStepMeaning(step, scale),
                    style: text.bodySmall!.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            Text(
              l10n.helpSettingsHint,
              style: text.bodySmall!.copyWith(color: colors.inkMuted),
            ),
            SectionLabel(l10n.helpWarmupTitle),
            Text(l10n.helpWarmupBody),
            SectionLabel(l10n.helpDropTitle),
            Text(l10n.helpDropBody),
          ],
        ),
      ),
    );
  }
}
