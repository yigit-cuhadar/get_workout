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
import '../domain/rest.dart';
import '../domain/set_logging.dart';
import 'widgets/effort_question.dart';
import 'widgets/rest_panel.dart';
import 'widgets/set_panel.dart';
import 'rest_timer_cubit.dart';
import 'set_bar.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
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
        if (state.failure case final failure?) {
          showForgeSnackbar(
            context,
            message: failure is NetworkFailure
                ? l10n.errorNetwork
                : state.status == WorkoutStatus.finished
                ? l10n.workoutSaveAsProgramFailed(ProgramLimits.maxItemsPerDay)
                : l10n.workoutFinishFailed,
            error: true,
          );
          cubit.failureShown();
        }
        if (state.savedProgramId case final id?) {
          showForgeSnackbar(
            context,
            message: l10n.workoutSavedAsProgram,
            actionLabel: l10n.workoutViewProgram,
            onAction: () => context.go(Routes.program(id, created: true)),
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
        _ => const _Loading(),
      },
    );
  }
}

/// The workout loading: shimmering bars where the header, an open card
/// with its bubbles, two closed cards and the set panel will be.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    Widget card(List<Widget> children) => DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: Border.all(color: colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: children,
        ),
      ),
    );
    const bubble = SkeletonBar(width: 40, height: 40, radius: 20);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ForgeAppBar.valueHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, Gap.md, 14, Gap.xs),
                child: Row(
                  spacing: 10,
                  children: [
                    ForgeIcon(ForgeIcons.expandMore, color: colors.inkMuted),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          SkeletonBar(widthFactor: 0.3, height: 24),
                          SkeletonBar(widthFactor: 0.45, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Gap.sm,
                  children: [
                    card(const [
                      SkeletonBar(widthFactor: 0.45, height: 14),
                      SkeletonBar(widthFactor: 0.7, height: 10),
                      SkeletonBar(widthFactor: 0.5, height: 10),
                      Wrap(
                        spacing: Gap.sm,
                        children: [bubble, bubble, bubble, bubble, bubble],
                      ),
                    ]),
                    for (var i = 0; i < 2; i++)
                      card(const [
                        SkeletonBar(widthFactor: 0.45, height: 14),
                        SkeletonBar(widthFactor: 0.4, height: 10),
                      ]),
                  ],
                ),
              ),
            ),
            SetPanel.showing(
              child: Padding(
                padding: SetPanel.padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    const SkeletonBar(widthFactor: 0.5, height: 14),
                    const Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: SkeletonBar(
                            widthFactor: 1,
                            height: 50,
                            radius: 25,
                          ),
                        ),
                        Expanded(
                          child: SkeletonBar(
                            widthFactor: 1,
                            height: 50,
                            radius: 25,
                          ),
                        ),
                      ],
                    ),
                    SkeletonBar(
                      widthFactor: 1,
                      height: 52,
                      radius: style.radii.md,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The exercises above the bottom panel ([_Panel]), the header on top
/// with the time since the start; an empty workout says how to begin.
class _ActiveWorkout extends StatelessWidget {
  const _ActiveWorkout(this.state);
  final ActiveWorkoutState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final workout = state.workout!;
    final seen = context.select(
      (SettingsCubit cubit) =>
          cubit.state.loaded ? cubit.state.settings.seenTips : null,
    );
    final full = workout.exercises.length >= WorkoutLimits.maxExercises;
    void add() => _addExercises(context, workout);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(cubit.leave());
      },
      child: Scaffold(
        appBar: _Header(state),
        body: SetBarLayout(
          panel: workout.isEmpty
              ? const SizedBox.shrink()
              : _Panel(state: state),
          content: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverList.list(
                children: [
                  if (autoWarmupsTipDue(seen, added: state.warmupsAdded))
                    Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: TipBanner(
                        message: l10n.tipAutoWarmups,
                        dismissLabel: l10n.tipDismiss,
                        onDismiss: () => context.read<SettingsCubit>().tipSeen(
                          Tip.autoWarmups,
                        ),
                      ),
                    ),
                  if (workout.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: EmptyView(
                        icon: ForgeIcons.fitnessCenter,
                        message: l10n.workoutEmpty,
                        actions: [
                          ForgeButton(
                            label: l10n.programAddExercises,
                            leadingIcon: ForgeIcons.add,
                            onPressed: add,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              ExerciseCards(
                state: state,
                editor: cubit,
                running: cubit,
                picker: Routes.workoutPicker,
                exerciseRoute: Routes.workoutExercise,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.xl),
                sliver: SliverList.list(
                  children: [
                    if (!workout.isEmpty && !full)
                      Padding(
                        padding: const EdgeInsets.all(Gap.sm),
                        child: ForgeAddButton(
                          label: l10n.programAddExercises,
                          onPressed: add,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: NoteField(
                        initial: workout.note,
                        label: l10n.workoutNote,
                        hint: l10n.workoutNoteHint,
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
}

/// Minimize, the time since the start large, the workout's name with the
/// selected exercise's place under it, Finish (its loading state while it
/// finishes) and ⋯ with Discard workout.
class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header(this.state);
  final ActiveWorkoutState state;

  @override
  Size get preferredSize => const Size.fromHeight(ForgeAppBar.valueHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workout = state.workout!;
    final finishing = state.status == WorkoutStatus.finishing;
    return EverySecond(
      builder: (context) => ForgeAppBar.value(
        leading: ForgeAppBarAction.icon(
          icon: ForgeIcons.expandMore,
          label: l10n.workoutMinimize,
          onPressed: () => context.pop(),
        ),
        value: l10n.elapsedText(DateTime.now().difference(workout.startedAt)),
        subtitle: l10n.workoutHeaderLine(workout, state.selection),
        actions: [
          ForgeButton(
            label: l10n.workoutFinish,
            onPressed: () => finishWorkout(context, state),
            size: ForgeButtonSize.small,
            loading: finishing,
          ),
          Builder(
            builder: (button) => ForgeAppBarAction.icon(
              icon: ForgeIcons.moreHoriz,
              label: l10n.workoutMenu,
              onPressed: finishing
                  ? null
                  : () => showForgeMenu(
                      context: button,
                      items: [
                        ForgeMenuItem(
                          label: l10n.workoutDiscard,
                          destructive: true,
                          onTap: () => _discard(context, state),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _discard(BuildContext context, ActiveWorkoutState state) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    if (state.workout!.isEmpty ||
        await confirmChoice(
          context,
          title: l10n.workoutDiscardTitle,
          body: l10n.workoutDiscardBody,
          cancel: l10n.cancel,
          confirm: l10n.workoutDiscardConfirm,
          destructive: true,
        )) {
      await cubit.discard();
    }
  }
}

/// Finishes the workout of [state] after asking what needs asking: nothing
/// for an empty one, discarding when no set is ticked, and whether to
/// leave the unticked sets out.
Future<void> finishWorkout(
  BuildContext context,
  ActiveWorkoutState state,
) async {
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
      destructive: true,
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
        cancel: l10n.workoutKeepGoing,
        confirm: l10n.workoutFinishAnyway,
      )) {
    return;
  }
  await cubit.finish();
}

/// The bottom panel of the workout in progress, as [workoutPanel] picks:
/// the effort question or the selected set ([SetBar], under the rest's
/// line while one runs), the rest's countdown ([RestPanel]) and its end,
/// or Finish workout once every set is done. Asks once whether to notify
/// when a rest is over. Only this rebuilds as the seconds pass.
class _Panel extends StatelessWidget {
  const _Panel({required this.state});
  final ActiveWorkoutState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    return BlocConsumer<RestTimerCubit, RestTimerState>(
      listenWhen: (previous, current) =>
          current.askNotify && !previous.askNotify,
      listener: (context, _) => _askNotify(context),
      buildWhen: (previous, current) =>
          previous.phase != current.phase ||
          previous.remainingS != current.remainingS ||
          previous.totalS != current.totalS,
      builder: (context, rest) {
        final workout = state.workout!;
        final panel = workoutPanel(
          asking: state.questionRef != null && cubit.canEdit,
          entryWaitsForRest: state.entryWaitsForRest,
          allDone: !workout.hasUndoneSets && workout.doneSetCount > 0,
          doneSetPicked: state.doneSetPicked,
          phase: rest.phase,
        );
        String next() {
          final after = state.rest?.after;
          final to = nextSet(workout, after);
          return l10n.restPanelNextText(
            workout,
            to,
            after,
            to == null ? _noValues : state.suggestion(to),
            unit,
          );
        }

        // What does not fit the panel's share of the page scrolls.
        Widget showing(Widget child) =>
            SetPanel.showing(child: SingleChildScrollView(child: child));
        return switch (panel) {
          WorkoutPanel.question || WorkoutPanel.entry => SetBar(
            state: state,
            editor: cubit,
            loadPlates: cubit.loadPlates,
            rest: rest.phase == RestPhase.running
                ? EffortRest(
                    time: l10n.elapsedText(Duration(seconds: rest.remainingS)),
                    progress: rest.progress,
                    onAddTime: cubit.extendRest,
                    onSkip: cubit.skipRest,
                  )
                : null,
          ),
          WorkoutPanel.rest => showing(
            RestPanel(
              time: l10n.elapsedText(Duration(seconds: rest.remainingS)),
              progress: rest.progress,
              next: next(),
              onAddTime: cubit.extendRest,
              onSkip: cubit.skipRest,
            ),
          ),
          WorkoutPanel.restOver => showing(
            RestPanel.over(time: l10n.elapsedText(Duration.zero), next: next()),
          ),
          WorkoutPanel.finish => showing(
            Padding(
              padding: SetPanel.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Text(
                    l10n.restPanelAllSetsDone,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ForgeButton(
                    label: l10n.workoutFinishWorkout,
                    onPressed: () => finishWorkout(context, state),
                    size: ForgeButtonSize.large,
                    loading: state.status == WorkoutStatus.finishing,
                  ),
                ],
              ),
            ),
          ),
        };
      },
    );
  }

  static const SetValues _noValues = (
    weightKg: null,
    reps: null,
    durationS: null,
  );

  Future<void> _askNotify(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final timer = context.read<RestTimerCubit>();
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ForgeDialog(
        title: l10n.restNotifyQuestion,
        message: l10n.restNotifyBody,
        action: ForgeButton(
          label: l10n.restNotifyAllow,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.restNotifyLater,
          onPressed: () => Navigator.pop(context, false),
          variant: ForgeButtonVariant.text,
        ),
      ),
    );
    await timer.answerNotify(allow: allow ?? false);
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
