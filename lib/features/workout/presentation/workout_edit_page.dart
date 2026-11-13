import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/max_length_formatter.dart';
import '../../../core/unsaved_changes.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart';
import 'exercise_cards.dart';
import 'number_cell.dart';
import 'set_bar.dart';
import 'workout_edit_cubit.dart';
import 'workout_editor_view.dart';

/// Edits stored workout [id], or, without one, adds a past workout.
class WorkoutEditPage extends StatelessWidget {
  const WorkoutEditPage({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) {
    // Read here: a provider's create callback may not listen to the locale.
    final freeName = AppLocalizations.of(context).workoutFreeName;
    return BlocProvider(
      create: (_) => sl<WorkoutEditCubit>(param1: id, param2: freeName),
      child: const _EditView(),
    );
  }
}

class _EditView extends StatelessWidget {
  const _EditView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    Future<bool> confirmDiscard() => confirmChoice(
      context,
      title: l10n.historyDiscardTitle,
      body: null,
      cancel: l10n.programKeepEditing,
      confirm: l10n.workoutDiscardConfirm,
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
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
          cubit.problemShown();
        },
        builder: (context, state) {
          final editing =
              state.status == WorkoutEditStatus.editing ||
              state.status == WorkoutEditStatus.saving;
          return PopScope(
            canPop: !cubit.hasChanges,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (await UnsavedChangesGuard.ask(context) && context.mounted) {
                context.pop();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  cubit.isNew ? l10n.historyPastTitle : l10n.historyEditTitle,
                ),
              ),
              body: switch (state.status) {
                WorkoutEditStatus.missing => EmptyView(
                  message: l10n.historyNotFound,
                ),
                WorkoutEditStatus.syncing => EmptyView(
                  message: l10n.historySyncing,
                ),
                WorkoutEditStatus.failure => ErrorView(
                  message: l10n.historyLoadFailed,
                  retryLabel: l10n.retry,
                  onRetry: cubit.retry,
                ),
                _ when !editing => const LoadingView(),
                _ => _Form(state),
              },
            ),
          );
        },
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form(this.state);
  final WorkoutEditState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    final workout = state.workout!;
    final start = workout.startedAt;
    final duration = (workout.finishedAt ?? start).difference(start);
    final saving = state.status == WorkoutEditStatus.saving;
    final conflict = state.conflict;
    return SetBarLayout(
      state: state,
      editor: cubit,
      content: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverList.list(
            children: [
              if (saving) const LinearProgressIndicator(),
              if (conflict != null)
                MaterialBanner(
                  content: Text(
                    conflict == WorkoutEditConflict.changed
                        ? l10n.historyChangedElsewhere
                        : l10n.historyDeletedElsewhere,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(l10n.historyDiscardChanges),
                    ),
                    if (conflict == WorkoutEditConflict.changed)
                      TextButton(
                        onPressed: cubit.reload,
                        child: Text(l10n.historyReload),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: TextFormField(
                  initialValue: workout.name,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    maxLengthFormatter(WorkoutLimits.maxNameLength),
                  ],
                  decoration: InputDecoration(labelText: l10n.historyName),
                  onChanged: cubit.setName,
                ),
              ),
              ListTile(
                title: Text(l10n.historyDate),
                trailing: Text(dates.formatMediumDate(start)),
                onTap: () => _pickDate(context, start),
              ),
              ListTile(
                title: Text(l10n.historyStartTime),
                trailing: Text(TimeOfDay.fromDateTime(start).format(context)),
                onTap: () => _pickTime(context, start),
              ),
              // Show the duration as stored: minutes past 59 carry into hours,
              // and more than 24 hours is cut.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.workoutDuration)),
                    Expanded(
                      child: NumberCell(
                        value: duration.inHours.toDouble(),
                        hint: l10n.historyHours,
                        onChanged: (text) => cubit.setTotalDuration(
                          Duration(
                            hours: int.tryParse(text) ?? 0,
                            minutes: duration.inMinutes % 60,
                          ),
                        ),
                      ),
                    ),
                    Text(l10n.historyHours),
                    Expanded(
                      child: NumberCell(
                        value: (duration.inMinutes % 60).toDouble(),
                        hint: l10n.historyMinutes,
                        onChanged: (text) => cubit.setTotalDuration(
                          Duration(
                            hours: duration.inHours,
                            minutes: int.tryParse(text) ?? 0,
                          ),
                        ),
                      ),
                    ),
                    Text(l10n.historyMinutes),
                  ],
                ),
              ),
              if (workout.exercises.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Text(l10n.workoutEmpty, textAlign: TextAlign.center),
                ),
            ],
          ),
          ExerciseCards(
            state: state,
            editor: cubit,
            picker: Routes.historyPicker,
            exerciseRoute: Routes.historyExercise,
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            sliver: SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(l10n.programAddExercises),
                    onPressed:
                        workout.exercises.length >= WorkoutLimits.maxExercises
                        ? null
                        : () => _addExercises(context, workout),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  child: NoteField(
                    initial: workout.note,
                    label: l10n.workoutNote,
                    maxLength: WorkoutLimits.maxNoteLength,
                    onChanged: cubit.setNote,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: ForgeButton(
                    label: l10n.historySave,
                    loading: saving,
                    onPressed: saving || conflict != null
                        ? null
                        : () => _save(context, workout),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addExercises(BuildContext context, Workout workout) async {
    final cubit = context.read<WorkoutEditCubit>();
    final language = Localizations.localeOf(context).languageCode;
    final picked = await context.push<List<Exercise>>(
      Routes.historyPicker(
        max: WorkoutLimits.maxExercises - workout.exercises.length,
        multiple: true,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      cubit.addExercises(picked, language);
    }
  }

  /// Unticked sets are left out, after asking.
  Future<void> _save(BuildContext context, Workout workout) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutEditCubit>();
    final undone = workout.exercises.fold(
      0,
      (count, e) => count + e.sets.where((s) => !s.done).length,
    );
    if (undone > 0 &&
        workout.doneSetCount > 0 &&
        !await confirmChoice(
          context,
          title: l10n.historyUnticked,
          body: l10n.workoutUnfinishedBody(undone),
          cancel: l10n.programKeepEditing,
          confirm: l10n.historySave,
        )) {
      return;
    }
    await cubit.save();
  }

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    final cubit = context.read<WorkoutEditCubit>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null) return;
    cubit.setStart(
      DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      ),
    );
  }

  Future<void> _pickTime(BuildContext context, DateTime current) async {
    final cubit = context.read<WorkoutEditCubit>();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    cubit.setStart(
      DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      ),
    );
  }
}
