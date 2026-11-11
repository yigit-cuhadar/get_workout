import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/grouping.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../../core/text_length.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import 'active_workout_cubit.dart';
import 'elapsed_text.dart';
import 'workout_set_row.dart';
import 'workout_text.dart';

/// The workout in progress, full screen above the tabs; back minimizes it
/// to the bar. Once finished it shows the summary.
class WorkoutPage extends StatelessWidget {
  const WorkoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    return BlocConsumer<ActiveWorkoutCubit, ActiveWorkoutState>(
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          current.failure != null ||
          previous.savedProgramId != current.savedProgramId,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.failure case final failure?) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                failure is NetworkFailure
                    ? l10n.errorNetwork
                    : state.status == WorkoutStatus.finished
                    ? l10n.workoutSaveAsProgramFailed(
                        ProgramLimits.maxItemsPerDay,
                      )
                    : l10n.workoutFinishFailed,
              ),
            ),
          );
          cubit.failureShown();
        }
        if (state.savedProgramId case final id?) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.workoutSavedAsProgram),
              action: SnackBarAction(
                label: l10n.workoutViewProgram,
                onPressed: () => context.go(Routes.program(id, created: true)),
              ),
            ),
          );
        }
        // Discarded, put away after the summary, or another user.
        if (state.status == WorkoutStatus.none ||
            state.status == WorkoutStatus.loading) {
          context.canPop() ? context.pop() : context.go(Routes.home);
        }
      },
      builder: (context, state) => switch (state.status) {
        WorkoutStatus.finished => _Summary(state),
        WorkoutStatus.active ||
        WorkoutStatus.finishing => _ActiveWorkout(state),
        _ => Scaffold(appBar: AppBar(), body: const LoadingView()),
      },
    );
  }
}

enum _WorkoutAction { reorder, discard }

class _ActiveWorkout extends StatelessWidget {
  const _ActiveWorkout(this.state);
  final ActiveWorkoutState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final workout = state.workout!;
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final finishing = state.status == WorkoutStatus.finishing;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.workoutMinimize,
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(workout.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ElapsedText(
              since: workout.startedAt,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: finishing ? null : () => _finish(context),
            child: Text(l10n.workoutFinish),
          ),
          PopupMenuButton<_WorkoutAction>(
            tooltip: l10n.workoutMenu,
            enabled: !finishing,
            onSelected: (action) => switch (action) {
              _WorkoutAction.reorder => _reorder(context),
              _WorkoutAction.discard => _discard(context),
            },
            itemBuilder: (_) => [
              if (workout.exercises.length > 1)
                PopupMenuItem(
                  value: _WorkoutAction.reorder,
                  child: Text(l10n.workoutReorder),
                ),
              PopupMenuItem(
                value: _WorkoutAction.discard,
                child: Text(l10n.workoutDiscard),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xl),
        children: [
          if (finishing) const LinearProgressIndicator(),
          if (workout.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Text(l10n.workoutEmpty, textAlign: TextAlign.center),
            ),
          for (final index in workout.exercises.indexed.map((e) => e.$1))
            _ExerciseSection(
              index: index,
              state: state,
              unit: settings.weightUnit,
              effort: settings.effortScale,
            ),
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.programAddExercises),
              onPressed: workout.exercises.length >= WorkoutLimits.maxExercises
                  ? null
                  : () => _addExercises(context, workout),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: _NoteField(
              initial: workout.note,
              label: l10n.workoutNote,
              maxLength: WorkoutLimits.maxNoteLength,
              onChanged: cubit.setNote,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addExercises(BuildContext context, Workout workout) async {
    final cubit = context.read<ActiveWorkoutCubit>();
    final language = Localizations.localeOf(context).languageCode;
    final picked = await context.push<List<Exercise>>(
      Routes.workoutPicker(
        max: WorkoutLimits.maxExercises - workout.exercises.length,
        multiple: true,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      cubit.addExercises(picked, language);
    }
  }

  Future<void> _finish(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final workout = state.workout!;
    if (workout.doneSetCount == 0) {
      final discard = await _confirm(
        context,
        title: l10n.workoutNothingDoneTitle,
        body: l10n.workoutNothingDoneBody,
        cancel: l10n.programKeepEditing,
        confirm: l10n.workoutDiscard,
      );
      if (discard) await cubit.discard();
      return;
    }
    final undone = workout.exercises.fold(
      0,
      (count, e) => count + e.sets.where((s) => !s.done).length,
    );
    if (undone > 0 &&
        !await _confirm(
          context,
          title: l10n.workoutUnfinishedTitle,
          body: l10n.workoutUnfinishedBody(undone),
          cancel: l10n.programKeepEditing,
          confirm: l10n.workoutFinishAnyway,
        )) {
      return;
    }
    await cubit.finish();
  }

  Future<void> _discard(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    if (await _confirm(
      context,
      title: l10n.workoutDiscardTitle,
      body: l10n.workoutDiscardBody,
      cancel: l10n.cancel,
      confirm: l10n.workoutDiscardConfirm,
    )) {
      await cubit.discard();
    }
  }

  void _reorder(BuildContext context) {
    final cubit = context.read<ActiveWorkoutCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const _ReorderSheet()),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String? body,
  required String cancel,
  required String confirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}

enum _ExerciseAction { swap, link, ungroup, note, remove }

class _ExerciseSection extends StatelessWidget {
  const _ExerciseSection({
    required this.index,
    required this.state,
    required this.unit,
    required this.effort,
  });

  final int index;
  final ActiveWorkoutState state;
  final WeightUnit unit;
  final EffortScale effort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    final group = exercise.group;
    final (start, end) = groupRange(exercises, index);
    final last = state.stats[exercise.exerciseId]?.last;
    final details = [
      ?l10n.goalText(exercise, unit),
      if (last != null) l10n.lastTimeText(last.date),
      ?exercise.note,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group == null || index == start) const Divider(),
        if (group != null && index == start)
          ListTile(
            dense: true,
            title: Text(
              l10n.groupLabel(group, end - start),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ListTile(
          leading: group == null ? null : CircleAvatar(child: Text(group)),
          title: Text(exercise.name, style: theme.textTheme.titleMedium),
          subtitle: details.isEmpty ? null : Text(details.join('\n')),
          trailing: PopupMenuButton<_ExerciseAction>(
            tooltip: l10n.programItemActions,
            onSelected: (action) => switch (action) {
              _ExerciseAction.swap => _swap(context),
              _ExerciseAction.link => cubit.linkWithNext(index),
              _ExerciseAction.ungroup => cubit.ungroup(index),
              _ExerciseAction.note => _editNote(context, exercise),
              _ExerciseAction.remove => _remove(context, exercise),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _ExerciseAction.swap,
                child: Text(l10n.workoutSwap),
              ),
              if (canLinkWithNext(exercises, index))
                PopupMenuItem(
                  value: _ExerciseAction.link,
                  child: Text(
                    linkedSize(exercises, index) == 2
                        ? l10n.programMakeSuperset
                        : l10n.programMakeCircuit,
                  ),
                ),
              if (group != null)
                PopupMenuItem(
                  value: _ExerciseAction.ungroup,
                  child: Text(l10n.programUngroup),
                ),
              PopupMenuItem(
                value: _ExerciseAction.note,
                child: Text(
                  exercise.note == null
                      ? l10n.workoutAddNote
                      : l10n.workoutEditNote,
                ),
              ),
              PopupMenuItem(
                value: _ExerciseAction.remove,
                child: Text(l10n.programRemoveItem),
              ),
            ],
          ),
        ),
        SetHeading(type: exercise.loggingType, unit: unit),
        for (final (s, _) in exercise.sets.indexed)
          SetRow(
            ref: (exercise: index, set: s),
            state: state,
            unit: unit,
            effort: effort,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.workoutAddSet),
              onPressed: exercise.sets.length >= WorkoutLimits.maxSets
                  ? null
                  : () => cubit.addSet(index),
            ),
          ),
        ),
      ],
    );
  }

  /// The exercise's alternatives first, then the whole library.
  Future<void> _swap(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final language = Localizations.localeOf(context).languageCode;
    final owned = context.read<EquipmentCubit>().state.owned ?? const {};
    final alternatives = cubit.alternatives(index, owned).take(8).toList();
    const browse = Object();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.workoutSwapBrowse),
              onTap: () => Navigator.pop(context, browse),
            ),
            if (alternatives.isNotEmpty)
              ListTile(
                dense: true,
                title: Text(
                  l10n.workoutSwapAlternatives,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            for (final exercise in alternatives)
              ListTile(
                title: Text(exercise.localized(context).name),
                subtitle: Text(
                  l10n.exerciseSummary(
                    l10n.muscleNames(exercise.mainMuscles),
                    l10n.equipmentNames(exercise.equipment),
                  ),
                ),
                onTap: () => Navigator.pop(context, exercise),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    var replacement = choice is Exercise ? choice : null;
    if (identical(choice, browse)) {
      final picked = await context.push<List<Exercise>>(
        Routes.workoutPicker(max: 1, multiple: false),
      );
      replacement = picked?.firstOrNull;
    }
    if (replacement != null) {
      cubit.swapExercise(index, replacement, language);
    }
  }

  Future<void> _editNote(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final controller = TextEditingController(text: exercise.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exercise.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [_maxLength(WorkoutLimits.maxExerciseNoteLength)],
          decoration: InputDecoration(labelText: l10n.workoutExerciseNote),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.programSave),
          ),
        ],
      ),
    );
    if (saved == true) cubit.setExerciseNote(index, controller.text);
    controller.dispose();
  }

  Future<void> _remove(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    if (exercise.doneSets.isNotEmpty &&
        !await _confirm(
          context,
          title: l10n.workoutRemoveExerciseTitle,
          body: null,
          cancel: l10n.cancel,
          confirm: l10n.programRemoveItem,
        )) {
      return;
    }
    cubit.removeExercise(index);
  }
}

/// The exercises by name, reordered by dragging; groups move as one.
class _ReorderSheet extends StatelessWidget {
  const _ReorderSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final exercises = context.select(
      (ActiveWorkoutCubit cubit) => cubit.state.workout?.exercises ?? const [],
    );
    return SafeArea(
      child: ReorderableListView.builder(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        itemCount: exercises.length,
        onReorderItem: cubit.moveExercise,
        itemBuilder: (context, index) {
          final exercise = exercises[index];
          return ListTile(
            key: ValueKey(index),
            leading: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                semanticLabel: l10n.programReorder,
              ),
            ),
            title: Text(exercise.name),
            trailing: exercise.group == null ? null : Text(exercise.group!),
          );
        },
      ),
    );
  }
}

/// A multi-line note that applies every change at once.
class _NoteField extends StatefulWidget {
  const _NoteField({
    required this.initial,
    required this.label,
    required this.maxLength,
    required this.onChanged,
  });

  final String? initial;
  final String label;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: null,
    textCapitalization: TextCapitalization.sentences,
    inputFormatters: [_maxLength(widget.maxLength)],
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}

/// Cuts text to [max] code units, as the rules count them.
TextInputFormatter _maxLength(int max) =>
    TextInputFormatter.withFunction((_, value) {
      if (value.text.length <= max) return value;
      final text = cutToLength(value.text, max);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });

class _Summary extends StatelessWidget {
  const _Summary(this.state);
  final ActiveWorkoutState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final workout = state.workout!;
    final summary = state.summary!;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workoutDoneTitle),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          Text(workout.name, style: theme.textTheme.titleLarge),
          if (summary.records.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            _Celebration(count: summary.records.length),
          ],
          const SizedBox(height: Gap.md),
          ListTile(
            title: Text(l10n.workoutDuration),
            trailing: Text(l10n.durationMinutes(summary.duration)),
          ),
          ListTile(
            title: Text(l10n.workoutVolume),
            trailing: Text(l10n.weightText(summary.volumeKg, unit)),
          ),
          ListTile(
            title: Text(l10n.workoutSets),
            trailing: Text('${summary.setCount}'),
          ),
          ListTile(
            title: Text(l10n.workoutExercises),
            trailing: Text('${summary.exerciseCount}'),
          ),
          for (final record in summary.records)
            ListTile(
              leading: Icon(
                Icons.emoji_events,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.recordText(record, unit)),
            ),
          const SizedBox(height: Gap.lg),
          if (!workout.isFromProgram) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(l10n.workoutSaveAsProgram),
              onPressed: state.savingProgram || state.savedProgramId != null
                  ? null
                  : () => _saveAsProgram(context, workout.name),
            ),
            const SizedBox(height: Gap.sm),
          ],
          ForgeButton(label: l10n.libraryDone, onPressed: cubit.summaryShown),
        ],
      ),
    );
  }

  Future<void> _saveAsProgram(BuildContext context, String name) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final controller = TextEditingController(
      text: cutToLength(name, ProgramLimits.maxNameLength),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.workoutSaveAsProgram),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [_maxLength(ProgramLimits.maxNameLength)],
          decoration: InputDecoration(labelText: l10n.workoutSaveAsProgramName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.programSave),
          ),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await cubit.saveAsProgram(controller.text);
    }
    controller.dispose();
  }
}

/// A trophy that pops in once, with the count of new records.
class _Celebration extends StatelessWidget {
  const _Celebration({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.elasticOut,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Icon(
            Icons.emoji_events,
            color: theme.colorScheme.primary,
            size: theme.textTheme.displayLarge?.fontSize,
          ),
        ),
        Text(
          AppLocalizations.of(context).workoutNewRecords(count),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
