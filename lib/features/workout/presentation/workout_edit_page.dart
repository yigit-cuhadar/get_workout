import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/unsaved_changes.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../programs/domain/program.dart';
import '../domain/effort.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart';
import 'exercise_cards.dart';
import 'past_workout_pickers.dart';
import 'widgets/set_table.dart';
import 'widgets/set_type_menu.dart';
import 'workout_edit_cubit.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// Where a stored workout's edit page and the pages above it live, so they
/// stay in the tab it was opened from: the calendar's or Today's.
typedef WorkoutEditRoutes = ({
  String Function(String id) edit,
  String Function({required int max, required bool multiple}) picker,
  String Function(String id) exercise,
});

/// Edits stored workout [id], or, without one, adds a past workout as
/// [plan] has it (an hour ending this hour without one); the picker and
/// exercises open at [routes]. Pops with true once the workout is deleted.
class WorkoutEditPage extends StatelessWidget {
  const WorkoutEditPage({super.key, this.id, this.plan, required this.routes});

  final String? id;
  final PastWorkoutPlan? plan;
  final WorkoutEditRoutes routes;

  @override
  Widget build(BuildContext context) {
    // Read here: a provider's create callback may not listen to the locale.
    final plan =
        this.plan ??
        WorkoutEditCubit.defaultPlan(
          AppLocalizations.of(context).workoutFreeName,
          DateTime.now(),
          Localizations.localeOf(context).languageCode,
        );
    return BlocProvider(
      create: (_) => sl<WorkoutEditCubit>(param1: id, param2: plan),
      child: _EditView(routes),
    );
  }
}

class _EditView extends StatelessWidget {
  const _EditView(this.routes);
  final WorkoutEditRoutes routes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    Future<bool> confirmDiscard() => confirmChoice(
      context,
      title: l10n.historyDiscardTitle,
      body: l10n.historyDiscardBody,
      cancel: l10n.programKeepEditing,
      confirm: l10n.workoutDiscardConfirm,
      destructive: true,
    );
    return UnsavedChangesGuard(
      hasChanges: () => cubit.hasChanges,
      confirmDiscard: confirmDiscard,
      child: BlocConsumer<WorkoutEditCubit, WorkoutEditState>(
        listenWhen: (previous, current) =>
            previous.status != current.status ||
            current.issue != null ||
            current.failure != null,
        listener: (context, state) {
          if (state.status == WorkoutEditStatus.deleted) {
            context.pop(true);
            return;
          }
          if (state.status == WorkoutEditStatus.saved ||
              state.status == WorkoutEditStatus.closed) {
            context.pop();
            return;
          }
          if (state.status != WorkoutEditStatus.editing) return;
          final message = switch ((state.issue, state.failure)) {
            (WorkoutChangeIssue.noDoneSet, _) => l10n.historyNoDoneSet,
            (WorkoutChangeIssue.startInFuture, _) => l10n.historyStartInFuture,
            (WorkoutChangeIssue.endInFuture, _) => l10n.historyEndInFuture,
            (WorkoutChangeIssue.badDuration, _) => l10n.historyBadDuration,
            (WorkoutChangeIssue.invalid, _) => l10n.historyInvalid,
            (_, NetworkFailure()) => l10n.errorNetwork,
            (_, _?) => l10n.historySaveFailed,
            _ => null,
          };
          if (message == null) return;
          showForgeSnackbar(context, message: message, error: true);
          cubit.problemShown();
        },
        builder: (context, state) {
          final editing =
              state.status == WorkoutEditStatus.editing ||
              state.status == WorkoutEditStatus.saving ||
              state.status == WorkoutEditStatus.deleting;
          final canSave =
              state.status == WorkoutEditStatus.editing &&
              state.conflict == null;
          return PopScope(
            canPop: !cubit.hasChanges,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (await UnsavedChangesGuard.ask(context) && context.mounted) {
                context.pop();
              }
            },
            child: Scaffold(
              appBar: ForgeAppBar(
                title: cubit.isNew
                    ? l10n.historyPastTitle
                    : l10n.historyEditTitle,
                actions: [
                  if (editing)
                    ForgeAppBarAction.text(
                      label: l10n.historySave,
                      onPressed: canSave
                          ? () => _save(context, state.workout!)
                          : null,
                    ),
                ],
              ),
              body: switch (state.status) {
                WorkoutEditStatus.missing => EmptyView(
                  message: l10n.historyNotFound,
                ),
                WorkoutEditStatus.syncing => EmptyView(
                  message: l10n.historySyncing,
                ),
                WorkoutEditStatus.failure => ErrorView(
                  title: l10n.historyLoadFailed,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: cubit.retry,
                ),
                _ when !editing => const LoadingView(),
                _ => Column(
                  children: [
                    if (state.status != WorkoutEditStatus.editing)
                      Progress.indeterminate(label: l10n.workoutSaving),
                    Expanded(child: _Form(state, routes)),
                  ],
                ),
              },
            ),
          );
        },
      ),
    );
  }

  /// Unticked sets are left out, after asking.
  Future<void> _save(BuildContext context, Workout workout) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    final unticked = workout.exercises.fold(
      0,
      (count, e) => count + e.sets.where((s) => !s.done).length,
    );
    if (unticked > 0 &&
        workout.doneSetCount > 0 &&
        !await confirmChoice(
          context,
          title: l10n.historyUnticked,
          body: l10n.historyUntickedBody(unticked),
          cancel: l10n.programKeepEditing,
          confirm: l10n.historySave,
        )) {
      return;
    }
    await cubit.save();
  }
}

/// The workout's date and time and duration as rows opening their
/// pickers, a [SetTable] per exercise, Add exercises, the workout note,
/// and Discard (a new one) or Delete workout at the end.
class _Form extends StatefulWidget {
  const _Form(this.state, this.routes);
  final WorkoutEditState state;
  final WorkoutEditRoutes routes;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  /// The value boxes' controllers by set and field, and the value each was
  /// last set to, so a box being typed in is not rewritten.
  final _controllers = <Object, TextEditingController>{};
  final _shown = <Object, num?>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(Object key, num? value, String text) {
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: text),
    );
    if (!_shown.containsKey(key) || _shown[key] != value) {
      _shown[key] = value;
      if (controller.text != text) controller.text = text;
    }
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    final state = widget.state;
    final workout = state.workout!;
    final start = workout.startedAt;
    final duration = WorkoutEditCubit.duration(workout);
    final saving = state.status != WorkoutEditStatus.editing;
    final conflict = state.conflict;
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final full = workout.exercises.length >= WorkoutLimits.maxExercises;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.xl),
      children: [
        if (conflict != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NoticeBanner(
              icon: conflict == WorkoutEditConflict.changed
                  ? ForgeIcons.sync
                  : ForgeIcons.delete,
              title: conflict == WorkoutEditConflict.changed
                  ? l10n.historyChangedTitle
                  : l10n.historyDeletedTitle,
              message: conflict == WorkoutEditConflict.changed
                  ? l10n.historyChangedElsewhere
                  : l10n.historyDeletedElsewhere,
              action: Row(
                spacing: Gap.sm,
                children: [
                  Expanded(
                    child: ForgeButton(
                      label: l10n.historyDiscardChanges,
                      onPressed: () => context.pop(),
                      variant: ForgeButtonVariant.secondary,
                    ),
                  ),
                  if (conflict == WorkoutEditConflict.changed)
                    Expanded(
                      child: ForgeButton(
                        label: l10n.historyReload,
                        onPressed: cubit.reload,
                        variant: ForgeButtonVariant.secondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ListRowCard(
          children: [
            ListRow(
              title: l10n.historyDateTime,
              value: l10n.historyDateTimeValue(
                DateFormat.MMMEd(l10n.localeName).format(start),
                MaterialLocalizations.of(context)
                    .formatTimeOfDay(TimeOfDay.fromDateTime(start)),
              ),
              end: ListRowEnd.chevron,
              onTap: () => _pickStart(context, start),
            ),
            ListRow(
              title: l10n.workoutDuration,
              value: l10n.durationMinutes(duration),
              end: ListRowEnd.chevron,
              onTap: () => pickWorkoutDuration(
                context,
                duration,
                cubit.setTotalDuration,
              ),
            ),
          ],
        ),
        for (final (index, exercise) in workout.exercises.indexed) ...[
          const SizedBox(height: 10),
          _table(context, index, exercise, settings),
        ],
        const SizedBox(height: 10),
        if (!full)
          ForgeAddButton(
            label: l10n.programAddExercises,
            onPressed: () => _addExercises(context, workout),
          ),
        const SizedBox(height: 10),
        WorkoutNoteCard(note: workout.note, onSaved: cubit.setNote),
        const SizedBox(height: Gap.md),
        SizedBox(
          width: double.infinity,
          child: cubit.isNew
              ? ForgeButton(
                  label: l10n.workoutDiscardConfirm,
                  variant: ForgeButtonVariant.danger,
                  onPressed: () => context.pop(),
                )
              : ForgeButton(
                  label: l10n.historyDelete,
                  variant: ForgeButtonVariant.danger,
                  loading: state.status == WorkoutEditStatus.deleting,
                  onPressed: saving || conflict != null
                      ? null
                      : () => _delete(context),
                ),
        ),
      ],
    );
  }

  Widget _table(
    BuildContext context,
    int index,
    WorkoutExercise exercise,
    UserSettings settings,
  ) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    final unit = settings.weightUnit;
    final type = exercise.loggingType;
    final numbers = NumberFormat.decimalPattern(l10n.localeName);
    SetTableInput weight(Object key, double? kg, ValueChanged<String> set) {
      final shown = kg == null ? null : unit.shownFromKg(kg);
      return SetTableInput(
        label: l10n.weightUnitLabel(unit),
        wide: true,
        controller: _controller(
          key,
          shown,
          shown == null ? '' : l10n.weightField(kg!, unit),
        ),
        onChanged: (text) {
          set(text);
          _shown[key] = _shownWeight(cubit, key, unit);
        },
      );
    }

    SetTableInput count(
      Object key,
      int? value,
      String label,
      ValueChanged<String> set,
    ) => SetTableInput(
      label: label,
      controller: _controller(
        key,
        value,
        value == null ? '' : numbers.format(value),
      ),
      onChanged: (text) {
        set(text);
        _shown[key] = _shownCount(cubit, key);
      },
    );

    final rows = [
      for (final (i, set) in exercise.sets.indexed)
        () {
          final ref = (exercise: index, set: i);
          final rated = set.done && !set.isWarmup;
          return SetTableEditRow(
            label: l10n.setLabel(exercise, i),
            semanticLabel: l10n.setBubbleLabel(exercise, i),
            done: set.done,
            onToggle: () {
              FocusScope.of(context).unfocus();
              cubit.toggleDone(ref);
            },
            onOptions: (bubble) => _setOptions(bubble, ref),
            inputs: [
              if (type.logsWeight)
                weight(
                  (index, i, 'kg'),
                  set.weightKg,
                  (text) => cubit.setWeight(ref, text, unit),
                ),
              if (type.isDurationBased)
                count(
                  (index, i, 's'),
                  set.durationS,
                  l10n.setPanelSeconds,
                  (text) => cubit.setDuration(ref, text),
                )
              else
                count(
                  (index, i, 'reps'),
                  set.reps,
                  l10n.setPanelReps,
                  (text) => cubit.setReps(ref, text),
                ),
            ],
            effort: rated ? l10n.effortText(set, settings.effortScale) : null,
            onEffort: rated ? () => _effort(context, ref) : null,
            drops: [
              for (final (d, drop) in set.drops.indexed)
                [
                  if (type.logsWeight)
                    weight(
                      (index, i, d, 'kg'),
                      drop.weightKg,
                      (text) => cubit.setDropWeight(ref, d, text, unit),
                    ),
                  count(
                    (index, i, d, 'reps'),
                    drop.reps,
                    l10n.setPanelReps,
                    (text) => cubit.setDropReps(ref, d, text),
                  ),
                ],
            ],
            note: set.note,
          );
        }(),
    ];
    return SetTable.edit(
      name: exercise.name,
      group: exercise.group,
      note: exercise.note,
      rows: rows,
      menu: ExerciseMenu(
        index: index,
        state: widget.state,
        editor: cubit,
        running: null,
        picker: widget.routes.picker,
        exerciseRoute: widget.routes.exercise,
      ).items(context),
      onAddSet: exercise.sets.length >= WorkoutLimits.maxSets
          ? null
          : () => addSetOfKind(context, cubit, index),
    );
  }

  /// The value [key] holds now, as its box shows it.
  num? _shownWeight(WorkoutEditCubit cubit, Object key, WeightUnit unit) {
    final kg = switch (key) {
      (final int e, final int s, 'kg') =>
        cubit.state.workout!.exercises[e].sets[s].weightKg,
      (final int e, final int s, final int d, 'kg') =>
        cubit.state.workout!.exercises[e].sets[s].drops[d].weightKg,
      _ => null,
    };
    return kg == null ? null : unit.shownFromKg(kg);
  }

  num? _shownCount(WorkoutEditCubit cubit, Object key) {
    final exercises = cubit.state.workout!.exercises;
    return switch (key) {
      (final int e, final int s, 's') => exercises[e].sets[s].durationS,
      (final int e, final int s, 'reps') => exercises[e].sets[s].reps,
      (final int e, final int s, final int d, 'reps') =>
        exercises[e].sets[s].drops[d].reps,
      _ => null,
    };
  }

  /// The set type menu at [bubble], as on the workout screen.
  void _setOptions(BuildContext bubble, SetRef ref) {
    final l10n = AppLocalizations.of(bubble);
    final cubit = context.read<WorkoutEditCubit>();
    final exercise = cubit.state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    showSetTypeMenu(
      context: bubble,
      types: [
        for (final type in exercise.loggingType.setTypes)
          SetTypeMenuItem(
            label: l10n.setTypeLabel(type),
            bubble: l10n.setLabelAs(exercise, ref.set, type),
            warmup: type == SetType.warmup,
            current: type == set.type,
            onTap: () => cubit.setType(ref, type),
          ),
      ],
      removeLabel: l10n.workoutRemoveSet,
      onRemove: () => cubit.removeSet(ref),
    );
  }

  /// The effort of done set [ref] as rows in a sheet; picking the chosen
  /// step again clears it.
  Future<void> _effort(BuildContext context, SetRef ref) =>
      showForgeBottomSheet<void>(
        context: context,
        builder: (_) => BlocProvider.value(
          value: context.read<WorkoutEditCubit>(),
          child: _EffortSheet(ref),
        ),
      );

  /// The date first (up to today), then the start time on the wheel.
  Future<void> _pickStart(BuildContext context, DateTime current) async {
    final cubit = context.read<WorkoutEditCubit>();
    final picked = await pickWorkoutStart(context, current);
    if (picked != null) cubit.setStart(picked);
  }

  Future<void> _addExercises(BuildContext context, Workout workout) async {
    final cubit = context.read<WorkoutEditCubit>();
    final language = Localizations.localeOf(context).languageCode;
    final picked = await context.push<List<Exercise>>(
      widget.routes.picker(
        max: WorkoutLimits.maxExercises - workout.exercises.length,
        multiple: true,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      cubit.addExercises(picked, language);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    if (await confirmChoice(
      context,
      title: l10n.historyDeleteTitle,
      body: l10n.historyDeleteBody,
      cancel: l10n.cancel,
      confirm: l10n.historyDeleteConfirm,
      destructive: true,
    )) {
      await cubit.delete();
    }
  }
}

/// The effort of done set [ref] as the workout screen asks it: the
/// scale's question ("How hard was set 1?", "RIR", "RPE"), the set's
/// values under it, then the rows; picking the chosen step again clears
/// it.
class _EffortSheet extends StatelessWidget {
  const _EffortSheet(this.ref);

  final SetRef ref;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final scale = settings.effortScale;
    return BlocBuilder<WorkoutEditCubit, WorkoutEditState>(
      builder: (context, state) {
        final exercise = state.workout!.exercises[ref.exercise];
        final set = exercise.sets[ref.set];
        final steps = scale.steps;
        final chosen = scale.stepOf(set);
        return ForgeBottomSheet(
          title: l10n.effortAskTitle(scale, exercise, ref.set),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.sm,
            children: [
              Text(
                l10n.setWithDropsText(
                  set,
                  exercise.loggingType,
                  settings.weightUnit,
                ),
                style: ForgeStyle.of(context).data
                    .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
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
                  context.read<WorkoutEditCubit>().setEffort(
                    ref,
                    step == chosen ? null : step,
                  );
                  Navigator.pop(context);
                },
                form: ChoiceListForm.inline,
              ),
            ],
          ),
        );
      },
    );
  }
}
