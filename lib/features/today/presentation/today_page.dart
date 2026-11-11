import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../workout/presentation/start_workout.dart';

/// Placeholder for the Today tab, with the way to start an empty workout
/// until the tab is built.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: EmptyView(
        message: l10n.tabToday,
        action: ForgeButton(
          label: l10n.workoutStartEmpty,
          onPressed: () => startFreeWorkout(context),
        ),
      ),
    );
  }
}
