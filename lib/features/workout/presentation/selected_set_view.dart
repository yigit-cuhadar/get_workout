import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import 'keep_visible.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// [SetView.selectedSet]: of exercises [start] to [end] (one, or a superset
/// or circuit), only the selected set: where it is among its exercise's
/// sets, what it did last time, arrows to the exercise's other sets, and
/// adding a set. The other exercises of a group are picked by their header.
class SelectedSetView extends StatelessWidget {
  const SelectedSetView({
    super.key,
    required this.start,
    required this.end,
    required this.state,
    required this.editor,
  });

  final int start;
  final int end;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final selection = state.selection;
    if (selection == null ||
        selection.exercise < start ||
        selection.exercise >= end) {
      return const SizedBox.shrink();
    }
    final index = selection.exercise;
    final exercise = state.workout!.exercises[index];
    final set = selection.set;
    final previous = set == null
        ? null
        : state.lastTime((exercise: index, set: set));
    final full = exercise.sets.length >= WorkoutLimits.maxSets;
    final done = set != null && exercise.sets[set].done;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
      child: Column(
        children: [
          if (set == null)
            Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Text(l10n.workoutNoSets),
            )
          else
            KeepVisible(
              key: ValueKey(selection),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.workoutPreviousSet,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: set > 0 ? () => editor.stepSet(-1) : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: Gap.xs,
                          children: [
                            Flexible(
                              child: _Position(
                                text: [
                                  if (end - start > 1)
                                    groupItemLabel(
                                      state.workout!.exercises,
                                      index,
                                    ),
                                  l10n.setPositionText(exercise, set),
                                ].join(' · '),
                                done: done,
                              ),
                            ),
                            if (done)
                              Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              ),
                          ],
                        ),
                        if (previous != null)
                          Text(
                            l10n.workoutLastTimeSet(
                              l10n.setWithUnitText(
                                previous,
                                exercise.loggingType,
                                unit,
                              ),
                            ),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.workoutNextSet,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: set < exercise.sets.length - 1
                        ? () => editor.stepSet(1)
                        : null,
                  ),
                ],
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l10n.workoutAddSet),
            onPressed: full ? null : () => addSetOfKind(context, editor, index),
          ),
        ],
      ),
    );
  }
}

class _Position extends StatelessWidget {
  const _Position({required this.text, required this.done});

  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium,
    textAlign: TextAlign.center,
    semanticsLabel: done
        ? AppLocalizations.of(context).workoutBubbleDone(text)
        : text,
  );
}
