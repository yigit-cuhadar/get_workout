import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';
import 'workout_detail_cubit.dart';
import 'workout_editor_view.dart';
import 'workout_summary_card.dart';
import 'workout_text.dart';

/// A stored workout as it was logged, with its totals; it can be edited or
/// deleted once the server has its latest change.
class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => sl<WorkoutDetailCubit>(param1: id)),
      BlocProvider.value(value: sl<ProgramListCubit>()),
    ],
    child: const _DetailView(),
  );
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutDetailCubit>();
    return BlocConsumer<WorkoutDetailCubit, WorkoutDetailState>(
      listenWhen: (previous, current) =>
          previous.status != current.status || current.failure != null,
      listener: (context, state) {
        if (state.status == WorkoutDetailStatus.deleted ||
            state.status == WorkoutDetailStatus.closed) {
          context.pop();
          return;
        }
        if (state.status == WorkoutDetailStatus.ready &&
            state.failure != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.failure is NetworkFailure
                    ? l10n.errorNetwork
                    : l10n.historyDeleteFailed,
              ),
            ),
          );
          cubit.failureShown();
        }
      },
      builder: (context, state) {
        final workout = state.workout;
        return Scaffold(
          appBar: AppBar(
            title: Text(workout?.name ?? ''),
            actions: [
              if (workout != null) ...[
                IconButton(
                  tooltip: l10n.historyEdit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: state.canChange
                      ? () => context.go(Routes.calendarWorkoutEdit(workout.id))
                      : null,
                ),
                IconButton(
                  tooltip: l10n.historyDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: state.canChange ? () => _delete(context) : null,
                ),
              ],
            ],
          ),
          body: switch (state.status) {
            WorkoutDetailStatus.missing => EmptyView(
              message: l10n.historyNotFound,
            ),
            WorkoutDetailStatus.failure when workout == null => ErrorView(
              message: l10n.historyLoadFailed,
              retryLabel: l10n.retry,
              onRetry: cubit.retry,
            ),
            _ when workout == null => const LoadingView(),
            _ => _Workout(state, workout),
          },
        );
      },
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<WorkoutDetailCubit>();
    if (await confirmChoice(
      context,
      title: l10n.historyDeleteTitle,
      body: l10n.historyDeleteBody,
      cancel: l10n.cancel,
      confirm: l10n.historyDeleteConfirm,
    )) {
      await cubit.delete();
    }
  }
}

class _Workout extends StatelessWidget {
  const _Workout(this.state, this.workout);
  final WorkoutDetailState state;
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final start = workout.startedAt;
    final note = workout.note;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xl),
      children: [
        if (state.status == WorkoutDetailStatus.deleting)
          const LinearProgressIndicator(),
        const SizedBox(height: Gap.sm),
        WorkoutSummaryCard(
          summary: summarizeWorkout(workout, const []),
          caption:
              '${dates.formatMediumDate(start)} · '
              '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
          program: _program(context, l10n),
        ),
        if (state.pending) ...[
          const SizedBox(height: Gap.sm),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(l10n.historySyncing),
            ),
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: Gap.sm),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(l10n.workoutNote, style: theme.textTheme.titleSmall),
              subtitle: Text(note),
            ),
          ),
        ],
        for (final exercise in workout.exercises) ...[
          const SizedBox(height: Gap.sm),
          _ExerciseCard(exercise: exercise, name: _name(context, exercise)),
        ],
      ],
    );
  }

  /// The catalogue's name, custom exercises included; the name stored with
  /// the workout for one no longer there.
  String _name(BuildContext context, WorkoutExercise exercise) {
    final catalogue = context.watch<ExerciseCatalogueCubit>().state;
    final known = catalogue is CatalogueReady
        ? catalogue.exercises
              .where((e) => e.id == exercise.exerciseId)
              .firstOrNull
        : null;
    return known?.localized(context).name ?? exercise.name;
  }

  /// The program it came from, once the programs are known.
  Widget? _program(BuildContext context, AppLocalizations l10n) {
    final id = workout.programId;
    final programs = context.watch<ProgramListCubit>().state;
    if (id == null || programs.status != ProgramListStatus.ready) return null;
    final program = programs.program(id);
    return program == null
        ? Text(l10n.historyProgramDeleted)
        : ActionChip(
            label: Text(l10n.historyFromProgram(program.name)),
            onPressed: () => context.go(Routes.program(id)),
          );
  }
}

/// An exercise as logged: its group letter, name and note over a table of
/// its sets, each drop on its own row under its set.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.name});

  final WorkoutExercise exercise;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final unit = settings.weightUnit;
    final type = exercise.loggingType;
    final note = exercise.note;
    final group = exercise.group;
    final columns = l10n.setColumns(type, unit);
    TableRow row(List<String> cells, {TextStyle? style}) => TableRow(
      children: [
        for (final cell in cells)
          Padding(
            padding: const EdgeInsets.only(right: Gap.md, bottom: Gap.xs),
            child: Text(cell, style: style),
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, Gap.xs, 0, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: group == null ? null : CircleAvatar(child: Text(group)),
              title: Text(name, style: theme.textTheme.titleMedium),
              subtitle: note == null ? null : Text(note),
            ),
            if (exercise.sets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  columnWidths: {columns.length - 1: const FlexColumnWidth()},
                  children: [
                    row(columns, style: theme.textTheme.labelMedium),
                    for (final (i, set) in exercise.sets.indexed) ...[
                      row([
                        l10n.setLabel(exercise, i),
                        ...l10n.setValues(set, type, unit),
                        l10n.setRemark(set, settings.effortScale),
                      ]),
                      for (final (d, drop) in set.drops.indexed)
                        row([
                          '',
                          ...l10n.setValues(
                            WorkoutSet(
                              weightKg: drop.weightKg,
                              reps: drop.reps,
                            ),
                            type,
                            unit,
                          ),
                          l10n.workoutDrop(d + 1),
                        ]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
