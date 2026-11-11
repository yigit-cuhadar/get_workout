import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../library_cubit.dart';
import '../vocabulary_labels.dart';
import 'exercise_tile.dart';

/// The exercises of the muscle selected in [LibraryCubit]. Completes when the
/// sheet closes.
Future<void> showMuscleSheet(BuildContext context) {
  final library = context.read<LibraryCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: library,
      child: DraggableScrollableSheet(
        expand: false,
        builder: (context, scrollController) =>
            _MuscleSheet(scrollController: scrollController),
      ),
    ),
  );
}

class _MuscleSheet extends StatelessWidget {
  const _MuscleSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen: (_, current) => current.selectedMuscle != null,
      builder: (context, state) {
        final muscle = state.selectedMuscle;
        final exercises = state.muscleExercises;
        if (muscle == null || exercises == null) return const SizedBox();
        return ListView(
          controller: scrollController,
          children: [
            ListTile(
              title: Text(
                l10n.muscleName(muscle),
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (exercises.main.isEmpty && exercises.alsoWorks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Text(l10n.muscleSheetEmpty),
              ),
            ..._section(l10n.muscleSheetMain, exercises.main),
            ..._section(l10n.muscleSheetAlsoWorks, exercises.alsoWorks),
          ],
        );
      },
    );
  }

  static List<Widget> _section(String title, List<Exercise> exercises) => [
    if (exercises.isNotEmpty) ...[
      ListTile(dense: true, title: Text(title)),
      for (final exercise in exercises) ExerciseTile(exercise),
    ],
  ];
}
