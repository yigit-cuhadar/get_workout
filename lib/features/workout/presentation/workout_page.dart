import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../../core/max_length_formatter.dart';
import '../../../core/text_length.dart';
import '../../programs/domain/program.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/workout.dart';
import '../domain/workout_tips.dart';
import 'active_workout_cubit.dart';
import 'elapsed_text.dart';
import 'exercise_cards.dart';
import 'rest_strip.dart';
import 'rest_timer_cubit.dart';
import 'set_bar.dart';
import 'workout_editor_view.dart';
import 'workout_help.dart';
import 'workout_summary_card.dart';
import 'workout_text.dart';

/// The workout in progress, full screen above the tabs; back minimizes it
/// to the bar, or ends it while it is empty. Once finished it shows the
/// summary. Each time it opens it starts on the next set to do (see
/// [ActiveWorkoutCubit.pageOpened]); pages opened above it and closed
/// again leave it as it was.
class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  @override
  void initState() {
    super.initState();
    context.read<ActiveWorkoutCubit>().pageOpened();
  }

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
        // Discarded, put away after the summary, or another user; not when
        // leaving the page ended it.
        if ((state.status == WorkoutStatus.none ||
                state.status == WorkoutStatus.loading) &&
            (ModalRoute.of(context)?.isActive ?? false)) {
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

enum _WorkoutAction { discard }

/// The exercises above the set bar, then the rest; see [SetBarLayout].
/// After a tick that starts a rest, the bar shows only the effort question
/// until the rest is over (see [ActiveWorkoutState.entryWaitsForRest]).
class _ActiveWorkout extends StatelessWidget {
  const _ActiveWorkout(this.state);
  final ActiveWorkoutState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final workout = state.workout!;
    final finishing = state.status == WorkoutStatus.finishing;
    final seen = context.select(
      (SettingsCubit cubit) =>
          cubit.state.loaded ? cubit.state.settings.seenTips : null,
    );
    final phase = context.select((RestTimerCubit timer) => timer.state.phase);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(cubit.leave());
      },
      child: Scaffold(
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
                _WorkoutAction.discard => _discard(context),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _WorkoutAction.discard,
                  child: Text(l10n.workoutDiscard),
                ),
              ],
            ),
          ],
        ),
        body: SetBarLayout(
          state: state,
          editor: cubit,
          entry: showsSetEntry(
            entryWaitsForRest: state.entryWaitsForRest,
            phase: phase,
          ),
          below: const RestBelowBar(child: RestStrip()),
          content: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverList.list(
                children: [
                  if (finishing) const LinearProgressIndicator(),
                  if (autoWarmupsTipDue(seen, added: state.warmupsAdded))
                    TipBanner(
                      text: l10n.tipAutoWarmups,
                      onDismiss: () => context.read<SettingsCubit>().tipSeen(
                        Tip.autoWarmups,
                      ),
                    ),
                  if (workout.exercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Text(
                        l10n.workoutEmpty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
              ExerciseCards(
                state: state,
                editor: cubit,
                picker: Routes.workoutPicker,
                exerciseRoute: Routes.workoutExercise,
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
                            workout.exercises.length >=
                                WorkoutLimits.maxExercises
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
                  ],
                ),
              ),
            ],
          ),
        ),
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
    // Nothing to lose, so nothing to confirm.
    if (workout.isEmpty) return cubit.discard();
    if (workout.doneSetCount == 0) {
      final discard = await confirmChoice(
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
        !await confirmChoice(
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
    if (state.workout!.isEmpty ||
        await confirmChoice(
          context,
          title: l10n.workoutDiscardTitle,
          body: l10n.workoutDiscardBody,
          cancel: l10n.cancel,
          confirm: l10n.workoutDiscardConfirm,
        )) {
      await cubit.discard();
    }
  }
}

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
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            WorkoutSummaryCard(
              summary: summary,
              caption: l10n.workoutDoneTitle,
              title: workout.name,
            ),
            if (summary.records.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              _Celebration(count: summary.records.length),
              const SizedBox(height: Gap.sm),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final record in summary.records)
                      ListTile(
                        leading: Icon(
                          Icons.emoji_events,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(record.name),
                        subtitle: Text(l10n.recordText(record, unit)),
                      ),
                  ],
                ),
              ),
            ],
            if (summary.programUnknown) ...[
              const SizedBox(height: Gap.sm),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.workoutProgramUnknown),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ForgeButton(
                label: l10n.libraryDone,
                onPressed: cubit.summaryShown,
              ),
              if (!workout.isFromProgram) ...[
                const SizedBox(height: Gap.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l10n.workoutSaveAsProgram),
                  onPressed: state.savingProgram || state.savedProgramId != null
                      ? null
                      : () => _saveAsProgram(context, workout.name),
                ),
              ],
            ],
          ),
        ),
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
          inputFormatters: [maxLengthFormatter(ProgramLimits.maxNameLength)],
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
