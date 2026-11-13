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
import '../domain/workout_tips.dart';
import 'number_cell.dart';
import 'workout_editor.dart';
import 'workout_help.dart';
import 'workout_text.dart';

/// A page logging a workout: [content] above, and at the bottom the
/// [SetBar], then [below] it (e.g. the rest), then the safe area, on one
/// surface. The bottom takes at most [maxBottomShare] of the page (of what
/// the keyboard leaves); the bar's drops and effort row scroll beyond
/// that, its title, values and tick always show (as the effort question's
/// set, Skip and steps do, its tip scrolling).
class SetBarLayout extends StatelessWidget {
  const SetBarLayout({
    super.key,
    required this.content,
    required this.state,
    required this.editor,
    this.below,
  });

  final Widget content;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final Widget? below;

  static const maxBottomShare = 0.6;

  /// Of the bottom, the most [below] takes; the bar keeps the rest.
  static const maxBelowShare = 0.4;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Expanded(child: content),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: constraints.maxHeight * maxBottomShare,
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SetBar(state: state, editor: editor),
                  ),
                  // Laid out first, so it is capped to leave the bar the
                  // most room; what does not fit scrolls inside it.
                  if (below case final below?)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            constraints.maxHeight *
                            maxBottomShare *
                            maxBelowShare,
                      ),
                      child: below,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The rest strip, out of the way while the keyboard is up so the
/// [SetBar] sits right on it. It stays mounted, so it still asks about
/// notifications; only it rebuilds as the keyboard moves.
class RestBelowBar extends StatefulWidget {
  const RestBelowBar({super.key, required this.child});

  final Widget child;

  @override
  State<RestBelowBar> createState() => _RestBelowBarState();
}

class _RestBelowBarState extends State<RestBelowBar>
    with WidgetsBindingObserver {
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _typing = _keyboardUp();
  }

  @override
  void didChangeMetrics() {
    final typing = _keyboardUp();
    if (typing != _typing) setState(() => _typing = typing);
  }

  /// The page's own insets are taken off by the scaffold, so the view's.
  bool _keyboardUp() => View.of(context).viewInsets.bottom > 0;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: _typing,
    child: MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: widget.child,
    ),
  );
}

/// The selected set of the workout [editor] edits: which one it is, its
/// values with the suggestion as hint, its drops, its effort when it is
/// done, its options and the tick; nothing while no set is selected. Right
/// after a working set is ticked it is [_EffortQuestion] instead.
class SetBar extends StatelessWidget {
  const SetBar({super.key, required this.state, required this.editor});

  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settingsState = context.select((SettingsCubit cubit) => cubit.state);
    final settings = settingsState.settings;
    final seen = settingsState.loaded ? settings.seenTips : null;
    final unit = settings.weightUnit;
    // Not while edits are refused (finishing): an answer would be lost.
    if (state.questionRef case final asked? when editor.canEdit) {
      return _EffortQuestion(
        asked: asked,
        state: state,
        editor: editor,
        tip: effortTipDue(seen),
      );
    }
    final selection = state.selection;
    final index = selection?.set;
    if (selection == null || index == null) return const SizedBox.shrink();
    final ref = (exercise: selection.exercise, set: index);
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    final type = exercise.loggingType;
    final hint = state.suggestion(ref);
    final previous = state.lastTime(ref);
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
                    if (set.type != SetType.normal)
                      Text(
                        l10n.setTypeHint(set.type),
                        style: theme.textTheme.bodySmall,
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
                  builder: (_) => _SetOptions(editor: editor),
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
          if (state.invalidSet == ref)
            Text(
              l10n.workoutSetInvalid,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          // What does not fit the bar's share of the page scrolls.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (set.type == SetType.drop)
                    _Drops(
                      ref: ref,
                      set: set,
                      type: type,
                      unit: unit,
                      editor: editor,
                    ),
                  if (state.effortRowRef case final rated?)
                    _EffortRow(rated: rated, state: state, editor: editor),
                ],
              ),
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

/// The effort of the selected set [rated], which is done: which set it
/// is, the help, and the steps.
class _EffortRow extends StatelessWidget {
  const _EffortRow({
    required this.rated,
    required this.state,
    required this.editor,
  });

  final SetRef rated;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = context.select(
      (SettingsCubit cubit) => cubit.state.settings.effortScale,
    );
    final exercise = state.workout!.exercises[rated.exercise];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.effortRowQuestion(scale, exercise, rated.set),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const WorkoutHelpButton(),
          ],
        ),
        EffortChoice(
          scale: scale,
          chosen: scale.stepOf(exercise.sets[rated.set]),
          onChosen: (step) {
            editor.setEffort(rated, step);
            context.read<SettingsCubit>().tipSeen(Tip.effort);
          },
        ),
      ],
    );
  }
}

/// The bar while it asks the effort of [asked], the working set just
/// ticked: the set and its values, the question with the help, the steps,
/// Skip, and the first time its [tip]. No field or tick, so nothing is
/// logged to the wrong set; any touch keeps the question from timing out.
class _EffortQuestion extends StatelessWidget {
  const _EffortQuestion({
    required this.asked,
    required this.state,
    required this.editor,
    required this.tip,
  });

  final SetRef asked;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final bool tip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = context.read<SettingsCubit>();
    final current = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final scale = current.effortScale;
    final workout = state.workout!;
    final set = workout.exercises[asked.exercise].sets[asked.set];
    return Listener(
      onPointerDown: (_) => editor.keepAsking(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.effortDoneText(
                      workout,
                      asked,
                      state.selection,
                      current.weightUnit,
                    ),
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    editor.skipEffort();
                    settings.tipSeen(Tip.effort);
                  },
                  child: Text(l10n.effortSkip),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.effortQuestion(scale),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                WorkoutHelpButton(
                  onOpen: editor.pauseAsking,
                  onClosed: editor.keepAsking,
                ),
              ],
            ),
            EffortChoice(
              scale: scale,
              chosen: scale.stepOf(set),
              onChosen: (step) {
                editor.setEffort(asked, step);
                // Used, so its tip has nothing left to tell.
                settings.tipSeen(Tip.effort);
              },
            ),
            if (tip)
              // Below the steps and scrolling, so it never pushes them or
              // Skip out of the bar's share of the page.
              Flexible(
                child: SingleChildScrollView(
                  child: TipBanner(
                    text: l10n.tipEffort,
                    onDismiss: () => settings.tipSeen(Tip.effort),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The steps of [scale] in a row, [chosen] selected; picking the chosen
/// one again clears it.
class EffortChoice extends StatelessWidget {
  const EffortChoice({
    super.key,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: Gap.xs,
        children: [
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

/// The selected set's kind, note and removal; every change applies at
/// once. It follows the selection, which follows the set when a change of
/// kind moves it.
class _SetOptions extends StatelessWidget {
  const _SetOptions({required this.editor});

  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<WorkoutEditor<EditedWorkout>, EditedWorkout>(
      bloc: editor,
      builder: (context, state) {
        final selection = state.selection;
        final index = selection?.set;
        if (selection == null || index == null) return const SizedBox.shrink();
        final ref = (exercise: selection.exercise, set: index);
        final exercise = state.workout!.exercises[ref.exercise];
        final set = exercise.sets[ref.set];
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
                    for (final type in exercise.loggingType.setTypes)
                      ChoiceChip(
                        label: Text(l10n.setTypeLabel(type)),
                        selected: set.type == type,
                        onSelected: (_) => editor.setType(ref, type),
                      ),
                  ],
                ),
                TextFormField(
                  key: ValueKey(ref),
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
