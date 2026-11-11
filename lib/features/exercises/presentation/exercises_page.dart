import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';

/// Placeholder for the Exercises tab.
class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: EmptyView(message: AppLocalizations.of(context).tabExercises),
  );
}
