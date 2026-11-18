import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../calculators/domain/calculation.dart';
import '../../calculators/domain/plates.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/effort.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import '../domain/workout_tips.dart';
import 'active_workout_cubit.dart';
import 'rest_timer_cubit.dart';
import 'widgets/effort_question.dart';
import 'workout_editor.dart';
import 'workout_help.dart';
import 'widgets/set_panel.dart';
import 'widgets/set_type_menu.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// What to load on the bar for a set's weight: see
/// [ActiveWorkoutCubit.loadPlates].
typedef PlateLoader = Calculation<PlateLoad> Function(
  double targetKg, {
  required double barKg,
  required List<Plate> plates,
});

/// A page logging a workout: [content] above, and at the bottom the
/// [panel] (a [SetBar], or what the workout in progress shows in its place)
/// over the safe area on the surface. The panel takes at most
/// [maxBottomShare] of the page (of what the keyboard leaves); what does
/// not fit scrolls inside it. What the panel leaves goes to [content].
class SetBarLayout extends StatelessWidget {
  const SetBarLayout({super.key, required this.content, required this.panel});

  final Widget content;
  final Widget panel;

  static const maxBottomShare = 0.6;

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
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(child: panel),
                ColoredBox(
                  color: ForgeStyle.of(context).colors.surface,
                  child: const SafeArea(top: false, child: SizedBox.shrink()),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The selected set of the workout [editor] edits as a [SetPanel]: which
/// one it is, its values in steppers with the suggestion as hint, its
/// drops, its effort when it is done, its options and the tick, under the
/// line of a running [rest]; nothing while no set is selected. Right
/// after a working set is
/// ticked it shows [_EffortQuestion] instead. Log set is always on: empty
/// values are logged as their hints; a tick refused for a value with
/// neither rings the empty fields and says so under them until the set
/// can be ticked. With [loadPlates], the weight of a
/// set (weight × reps or time) of an exercise on a barbell, trap bar or EZ
/// bar has a plate button showing its breakdown on the user's bar of that
/// kind and plates; the workout keeps no equipment, so the exercise is
/// looked up in the catalogue.
class SetBar extends StatelessWidget {
  const SetBar({
    super.key,
    required this.state,
    required this.editor,
    this.loadPlates,
    this.rest,
  });

  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final PlateLoader? loadPlates;
  final EffortRest? rest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsState = context.select((SettingsCubit cubit) => cubit.state);
    final settings = settingsState.settings;
    final seen = settingsState.loaded ? settings.seenTips : null;
    final unit = settings.weightUnit;
    // Not while edits are refused (finishing): an answer would be lost.
    if (state.questionRef case final asked? when editor.canEdit) {
      return SetPanel.showing(
        child: _EffortQuestion(
          asked: asked,
          state: state,
          editor: editor,
          tip: effortTipDue(seen),
        ),
      );
    }
    final selection = state.selection;
    final index = selection?.set;
    if (selection == null || index == null) {
      return const SizedBox.shrink();
    }
    final ref = (exercise: selection.exercise, set: index);
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    final type = exercise.loggingType;
    final bar = context.select(
      (ExerciseCatalogueCubit catalogue) => switch (catalogue.state) {
        CatalogueReady(:final exercises) =>
          exercises
              .where((known) => known.id == exercise.exerciseId)
              .firstOrNull
              ?.loadedBar,
        _ => null,
      },
    );
    final hint = state.suggestion(ref);
    final previous = state.lastTime(ref);
    final details = [
      if (previous != null)
        l10n.workoutLastTimeSet(l10n.setWithDropsText(previous, type, unit)),
      ?set.note,
    ];
    final blocked =
        !set.done && state.invalidSet == ref && editor.toggledSet(ref) == null;
    // Each empty field without a hint is ringed; with none such, the first.
    final weightMissing =
        type.logsWeight &&
        !type.weightOptional &&
        set.weightKg == null &&
        hint.weightKg == null;
    final countMissing = type.isDurationBased
        ? set.durationS == null && hint.durationS == null
        : set.reps == null && hint.reps == null;
    final weightInvalid =
        blocked && type.logsWeight && (weightMissing || !countMissing);
    final countInvalid = blocked && (countMissing || !weightInvalid);
    final values = [
      if (type.logsWeight)
        _weight(
          l10n,
          type,
          unit,
          set.weightKg,
          hint.weightKg,
          (text) => editor.setWeight(ref, text, unit),
          invalid: weightInvalid,
        ),
      if (type.isDurationBased)
        _count(
          l10n,
          set.durationS,
          hint.durationS,
          l10n.setPanelSeconds,
          durationStepS,
          WorkoutLimits.maxDurationS,
          (text) => editor.setDuration(ref, text),
          invalid: countInvalid,
        )
      else
        _count(
          l10n,
          set.reps,
          hint.reps,
          l10n.setPanelReps,
          1,
          WorkoutLimits.maxReps,
          (text) => editor.setReps(ref, text),
          invalid: countInvalid,
        ),
    ];
    return SetPanel(
      title: l10n.setToDo(exercise, ref.set),
      description: set.type == SetType.warmup
          ? l10n.setTypeHint(set.type)
          : null,
      details: [if (details.isNotEmpty) details.join(' · ')],
      labels: SetPanelLabels(
        log: l10n.workoutLogSet,
        done: l10n.setPanelDone,
        options: l10n.workoutSetOptions,
        addDrop: l10n.workoutAddDrop,
        removeDrop: l10n.workoutRemoveDrop,
        plates: l10n.setPanelPlates,
      ),
      onOptions: () => showForgeBottomSheet<void>(
        context: context,
        builder: (_) => _SetOptions(editor: editor),
      ),
      values: values,
      error: blocked ? l10n.workoutSetInvalid : null,
      drops: set.type == SetType.drop
          ? [
              for (final (d, drop) in set.drops.indexed)
                SetPanelDrop(
                  label: l10n.workoutDrop(d + 1),
                  values: [
                    if (type.logsWeight)
                      _weight(
                        l10n,
                        type,
                        unit,
                        drop.weightKg,
                        null,
                        (text) => editor.setDropWeight(ref, d, text, unit),
                      ),
                    _count(
                      l10n,
                      drop.reps,
                      null,
                      l10n.setPanelReps,
                      1,
                      WorkoutLimits.maxReps,
                      (text) => editor.setDropReps(ref, d, text),
                    ),
                  ],
                  onRemove: () => editor.removeDrop(ref, d),
                ),
            ]
          : null,
      onAddDrop: set.drops.length < WorkoutLimits.maxDrops
          ? () => editor.addDrop(ref)
          : null,
      effort: state.effortRowRef == null
          ? null
          : _EffortRow(
              rated: state.effortRowRef!,
              state: state,
              editor: editor,
            ),
      done: set.done,
      onLog: () => _toggle(context, ref),
      rest: rest,
      onPlates: switch ((loadPlates, bar, set.weightKg ?? hint.weightKg)) {
        (final loadPlates?, final bar?, final kg?)
            when type == LoggingType.weightReps ||
                type == LoggingType.weightDuration =>
          (button) => _showPlates(button, loadPlates, kg, bar, settings),
        _ => null,
      },
    );
  }

  /// The plate breakdown of [kg] under the plate [button]: the weight, the
  /// user's [bar] of that kind, the plates on each side ("No plates" at the
  /// bar's weight) and the closest load when the plates can't make it;
  /// below the bar, that it is lighter.
  void _showPlates(
    BuildContext button,
    PlateLoader loadPlates,
    double kg,
    Equipment bar,
    UserSettings settings,
  ) {
    final l10n = AppLocalizations.of(button);
    final unit = settings.weightUnit;
    final barKg = settings.barWeightKgFor(bar);
    final barText = l10n.liftedWeightText(barKg, unit);
    final facts = switch (loadPlates(
      kg,
      barKg: barKg,
      plates: settings.plates,
    )) {
      Calculated(:final value) => [
        (l10n.calcBar, barText),
        (
          l10n.plateCalculatorEachSide,
          value.perSide.isEmpty
              ? l10n.platesNone
              : l10n.platesEachSideText(value.perSide, unit),
        ),
        if (!value.exact)
          (
            l10n.plateCalculatorClosest,
            l10n.liftedWeightText(value.totalKg, unit),
          ),
      ],
      _ => null,
    };
    showForgeInfo(
      context: button,
      title: l10n.liftedWeightText(kg, unit),
      facts: facts ?? [(l10n.calcBar, barText)],
      note: facts == null ? l10n.platesLighterThanBar(barText) : null,
    );
  }

  /// A weight of [type] for a field: stored as kg, typed and stepped as
  /// [unit] shows it.
  SetPanelValue _weight(
    AppLocalizations l10n,
    LoggingType type,
    WeightUnit unit,
    double? kg,
    double? hintKg,
    ValueChanged<String> onChanged, {
    bool invalid = false,
  }) {
    final label = l10n.weightUnitLabel(unit);
    return SetPanelValue(
      value: kg == null ? null : unit.shownFromKg(kg),
      hint: hintKg == null ? null : unit.shownFromKg(hintKg),
      unit: switch (type) {
        LoggingType.weightedBodyweight => l10n.setPanelAdded(label),
        LoggingType.assistedBodyweight => l10n.setPanelAssist(label),
        _ => label,
      },
      step: unit.weightStep,
      min: 0,
      max: unit.shownFromKg(WorkoutLimits.maxWeightKg),
      signed: type == LoggingType.weightedBodyweight,
      invalid: invalid,
      onChanged: (value) =>
          onChanged(value == null ? '' : l10n.numberField(value)),
    );
  }

  /// Reps or seconds for a field.
  SetPanelValue _count(
    AppLocalizations l10n,
    int? value,
    int? hint,
    String unit,
    int step,
    int max,
    ValueChanged<String> onChanged, {
    bool invalid = false,
  }) => SetPanelValue(
    value: value?.toDouble(),
    hint: hint?.toDouble(),
    unit: unit,
    step: step.toDouble(),
    min: 1,
    max: max.toDouble(),
    invalid: invalid,
    onChanged: (value) =>
        onChanged(value == null ? '' : l10n.numberField(value)),
  );

  void _toggle(BuildContext context, SetRef ref) {
    FocusScope.of(context).unfocus();
    editor.toggleDone(ref);
  }
}

/// The effort of the selected set [rated], which is done: which set it
/// is, the help, and the steps as the same rows, each with its meaning, as
/// the [EffortQuestion].
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
    final steps = scale.steps;
    final chosen = scale.stepOf(exercise.sets[rated.set]);
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
            EffortHelpButton(onPressed: () => openWorkoutHelp(context)),
          ],
        ),
        ChoiceGrid.list(
          options: [
            for (final step in steps)
              ChoiceOption(
                label: l10n.effortStepLabel(step, scale),
                hint: l10n.effortStepShortMeaning(step, scale),
              ),
          ],
          selected: chosen == null ? null : steps.indexOf(chosen),
          onSelected: (index) {
            final step = steps[index];
            // Picking the chosen step again clears it.
            editor.setEffort(rated, step == chosen ? null : step);
            context.read<SettingsCubit>().tipSeen(Tip.effort);
          },
          form: ChoiceListForm.inline,
        ),
      ],
    );
  }
}

/// The bar while it asks the effort of [asked], the working set just
/// ticked, as an [EffortQuestion]: with the rest's line on top while the
/// rest its tick started runs, and the first time its [tip] under it. No
/// field or tick, so nothing is logged to the wrong set; any touch keeps
/// the question from timing out. Picking the chosen step again clears it.
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
    final settings = context.read<SettingsCubit>();
    final current = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final scale = current.effortScale;
    final workout = state.workout!;
    final exercise = workout.exercises[asked.exercise];
    final steps = scale.steps;
    final chosen = scale.stepOf(exercise.sets[asked.set]);
    final values = l10n.effortAskValues(
      workout,
      asked,
      state.selection,
      current.weightUnit,
    );
    final options = [
      for (final step in steps)
        ChoiceOption(
          label: l10n.effortStepLabel(step, scale),
          hint: l10n.effortStepShortMeaning(step, scale),
        ),
    ];
    void pick(int index) {
      final step = steps[index];
      editor.setEffort(asked, step == chosen ? null : step);
      // Used, so its tip has nothing left to tell.
      settings.tipSeen(Tip.effort);
    }

    return Listener(
      onPointerDown: (_) => editor.keepAsking(),
      child: BlocBuilder<RestTimerCubit, RestTimerState>(
        buildWhen: (previous, current) =>
            previous.phase != current.phase ||
            previous.remainingS != current.remainingS ||
            previous.totalS != current.totalS,
        builder: (context, rest) {
          final resting =
              state.askingWithRest && rest.phase == RestPhase.running;
          return EffortQuestion(
            question: resting
                ? l10n.effortAskTitle(scale, exercise, asked.set)
                : l10n.effortQuestionText(scale),
            values: resting
                ? values
                : l10n.effortDoneValues(
                    workout,
                    asked,
                    state.selection,
                    current.weightUnit,
                  ),
            options: options,
            selected: chosen == null ? null : steps.indexOf(chosen),
            onSelected: pick,
            onHelp: () async {
              editor.pauseAsking();
              await openWorkoutHelp(context);
              editor.keepAsking();
            },
            rest: resting ? _rest(context, rest) : null,
            tip: tip
                ? TipBanner(
                    message: l10n.tipEffort,
                    dismissLabel: l10n.tipDismiss,
                    onDismiss: () => settings.tipSeen(Tip.effort),
                  )
                : null,
          );
        },
      ),
    );
  }

  EffortRest _rest(BuildContext context, RestTimerState rest) {
    final workout = context.read<ActiveWorkoutCubit>();
    return EffortRest(
      time: AppLocalizations.of(context)
          .elapsedText(Duration(seconds: rest.remainingS)),
      progress: rest.progress,
      onAddTime: workout.extendRest,
      onSkip: workout.skipRest,
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
    return BlocBuilder<WorkoutEditor<EditedWorkout>, EditedWorkout>(
      bloc: editor,
      builder: (context, state) {
        final selection = state.selection;
        final index = selection?.set;
        if (selection == null || index == null) return const SizedBox.shrink();
        final ref = (exercise: selection.exercise, set: index);
        final exercise = state.workout!.exercises[ref.exercise];
        final set = exercise.sets[ref.set];
        return ForgeBottomSheet(
          title: l10n.setToDo(exercise, ref.set),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                SetTypeList(
                  types: [
                    for (final type in exercise.loggingType.setTypes)
                      SetTypeMenuItem(
                        label: l10n.setTypeLabel(type),
                        bubble: l10n.setLabelAs(exercise, ref.set, type),
                        warmup: type == SetType.warmup,
                        current: type == set.type,
                        onTap: () => editor.setType(ref, type),
                      ),
                  ],
                ),
                NoteField(
                  key: ValueKey(ref),
                  initial: set.note,
                  label: l10n.workoutSetNote,
                  hint: l10n.workoutNoteHint,
                  maxLength: WorkoutLimits.maxSetNoteLength,
                  onChanged: (text) => editor.setSetNote(ref, text),
                ),
                ListRow(
                  title: l10n.workoutRemoveSet,
                  leading: const ForgeIcon(ForgeIcons.delete),
                  destructive: true,
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
