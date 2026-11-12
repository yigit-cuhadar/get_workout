import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/effort.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import 'number_cell.dart';
import 'workout_editor.dart';
import 'workout_text.dart';

/// The bottom of a page logging a workout: the [SetBar], then [below] it
/// (e.g. the rest), then the safe area, on one surface.
class SetBarArea extends StatelessWidget {
  const SetBarArea({
    super.key,
    required this.state,
    required this.editor,
    this.below,
  });

  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final Widget? below;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetBar(state: state, editor: editor),
          ?below,
        ],
      ),
    ),
  );
}

/// The selected set of the workout [editor] edits: which one it is, its
/// values with the suggestion as hint, its drops, its effort, its options
/// and the tick; nothing while no set is selected.
class SetBar extends StatelessWidget {
  const SetBar({super.key, required this.state, required this.editor});

  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final unit = settings.weightUnit;
    final selection = state.selection;
    final index = selection?.set;
    if (selection == null || index == null) return const SizedBox.shrink();
    final ref = (exercise: selection.exercise, set: index);
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    final type = exercise.loggingType;
    final hint = state.suggestion(ref);
    final previous = state.setView == SetView.bubbles
        ? state.lastTime(ref)
        : null;
    final details = [
      if (previous != null)
        l10n.workoutLastTimeSet(l10n.setWithUnitText(previous, type, unit)),
      ?set.note,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.setToDo(exercise, ref.set),
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' · '),
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.workoutSetOptions,
                icon: const Icon(Icons.more_horiz),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => _SetOptions(ref: ref, editor: editor),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (type.logsWeight)
                Expanded(
                  child: NumberCell.weight(
                    key: ValueKey(('weight', ref)),
                    kg: set.weightKg,
                    unit: unit,
                    label: l10n.weightLabel(type, unit),
                    hint: hint.weightKg == null
                        ? null
                        : l10n.weightField(hint.weightKg!, unit),
                    onChanged: (text) => editor.setWeight(ref, text, unit),
                  ),
                ),
              Expanded(
                child: type.isDurationBased
                    ? NumberCell(
                        key: ValueKey(('duration', ref)),
                        value: set.durationS?.toDouble(),
                        label: l10n.workoutSeconds,
                        hint: hint.durationS?.toString(),
                        onChanged: (text) => editor.setDuration(ref, text),
                      )
                    : NumberCell(
                        key: ValueKey(('reps', ref)),
                        value: set.reps?.toDouble(),
                        label: l10n.workoutReps,
                        hint: hint.reps?.toString(),
                        onChanged: (text) => editor.setReps(ref, text),
                      ),
              ),
              IconButton.filledTonal(
                tooltip: set.done ? l10n.workoutUntick : l10n.workoutTick,
                isSelected: set.done,
                icon: const Icon(Icons.check),
                selectedIcon: const Icon(Icons.check_circle),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  editor.toggleDone(ref);
                },
              ),
            ],
          ),
          if (set.type == SetType.drop)
            _Drops(ref: ref, set: set, type: type, unit: unit, editor: editor),
          _EffortChoice(
            scale: settings.effortScale,
            chosen: settings.effortScale.stepOf(set),
            onChosen: (step) => editor.setEffort(ref, step),
          ),
          if (state.invalidSet == ref)
            Text(
              l10n.workoutSetInvalid,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

/// The drops of a drop set, each editable and removable, and adding one.
class _Drops extends StatelessWidget {
  const _Drops({
    required this.ref,
    required this.set,
    required this.type,
    required this.unit,
    required this.editor,
  });

  final SetRef ref;
  final WorkoutSet set;
  final LoggingType type;
  final WeightUnit unit;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (d, drop) in set.drops.indexed)
          Row(
            children: [
              Text(l10n.workoutDrop(d + 1)),
              if (type.logsWeight)
                Expanded(
                  child: NumberCell.weight(
                    key: ValueKey(('dropWeight', ref, d)),
                    kg: drop.weightKg,
                    unit: unit,
                    onChanged: (text) =>
                        editor.setDropWeight(ref, d, text, unit),
                  ),
                ),
              Expanded(
                child: NumberCell(
                  key: ValueKey(('dropReps', ref, d)),
                  value: drop.reps?.toDouble(),
                  onChanged: (text) => editor.setDropReps(ref, d, text),
                ),
              ),
              IconButton(
                tooltip: l10n.workoutRemoveDrop,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => editor.removeDrop(ref, d),
              ),
            ],
          ),
        if (set.drops.length < WorkoutLimits.maxDrops)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l10n.workoutAddDrop),
            onPressed: () => editor.addDrop(ref),
          ),
      ],
    );
  }
}

/// The steps of [scale] in a row, [chosen] selected; picking the chosen
/// one again clears it.
class _EffortChoice extends StatelessWidget {
  const _EffortChoice({
    required this.scale,
    required this.chosen,
    required this.onChosen,
  });

  final EffortScale scale;
  final EffortStep? chosen;
  final ValueChanged<EffortStep?> onChosen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: Gap.xs,
        children: [
          Text(l10n.workoutEffort, style: theme.textTheme.labelLarge),
          for (final step in scale.steps)
            ChoiceChip(
              showCheckmark: false,
              label: _StepLabel(
                label: l10n.effortStepLabel(step, scale),
                hint: l10n.effortStepHint(step, scale),
              ),
              selected: step == chosen,
              onSelected: (_) => onChosen(step == chosen ? null : step),
            ),
        ],
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.label, required this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    if (hint == null) return Text(label);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Text(hint, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// A set's kind, note and removal; every change applies at once.
class _SetOptions extends StatelessWidget {
  const _SetOptions({required this.ref, required this.editor});

  final SetRef ref;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<WorkoutEditor<EditedWorkout>, EditedWorkout>(
      bloc: editor,
      builder: (context, state) {
        final exercise = state.workout?.exercises.elementAtOrNull(ref.exercise);
        final set = exercise?.sets.elementAtOrNull(ref.set);
        if (exercise == null || set == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: Gap.md,
              right: Gap.md,
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Gap.sm,
                  children: [
                    for (final type in SetType.values)
                      if (type != SetType.drop || exercise.loggingType.logsReps)
                        ChoiceChip(
                          label: Text(l10n.setTypeLabel(type)),
                          selected: set.type == type,
                          onSelected: (_) => editor.setType(ref, type),
                        ),
                  ],
                ),
                TextFormField(
                  initialValue: set.note,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    maxLengthFormatter(WorkoutLimits.maxSetNoteLength),
                  ],
                  decoration: InputDecoration(labelText: l10n.workoutSetNote),
                  onChanged: (text) => editor.setSetNote(ref, text),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(l10n.workoutRemoveSet),
                  onTap: () {
                    Navigator.pop(context);
                    editor.removeSet(ref);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Switches between the two ways the open exercise shows its sets; see
/// [SetView].
class SetViewToggle extends StatelessWidget {
  const SetViewToggle(this.view, {super.key, required this.onPressed});

  final SetView view;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).workoutSetsView,
    isSelected: view == SetView.selectedSet,
    icon: const Icon(Icons.bubble_chart_outlined),
    selectedIcon: const Icon(Icons.view_carousel_outlined),
    onPressed: onPressed,
  );
}
