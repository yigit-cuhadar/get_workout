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
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';
import 'workout_detail_cubit.dart';
import 'workout_editor_view.dart';
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
                      ? () => context.go(Routes.historyEdit(workout.id))
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
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final unit = settings.weightUnit;
    final summary = summarizeWorkout(workout, const []);
    final start = workout.startedAt;
    final program = _programLine(context, l10n);
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      children: [
        if (state.status == WorkoutDetailStatus.deleting)
          const LinearProgressIndicator(),
        if (state.pending)
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(l10n.historySyncing),
          ),
        ListTile(
          title: Text(l10n.historyStarted),
          trailing: Text(
            '${dates.formatMediumDate(start)} '
            '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
          ),
        ),
        if (program != null)
          ListTile(leading: const Icon(Icons.event_note), title: program),
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
        if (workout.note case final note?)
          ListTile(title: Text(l10n.workoutNote), subtitle: Text(note)),
        for (final exercise in workout.exercises) ...[
          const Divider(),
          ListTile(
            leading: exercise.group == null
                ? null
                : CircleAvatar(child: Text(exercise.group!)),
            title: Text(
              _name(context, exercise),
              style: theme.textTheme.titleMedium,
            ),
            subtitle: exercise.note == null ? null : Text(exercise.note!),
          ),
          for (final (i, set) in exercise.sets.indexed)
            _SetLine(
              exercise: exercise,
              index: i,
              set: set,
              unit: unit,
              effort: settings.effortScale,
            ),
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
  Widget? _programLine(BuildContext context, AppLocalizations l10n) {
    final id = workout.programId;
    final programs = context.watch<ProgramListCubit>().state;
    if (id == null || programs.status != ProgramListStatus.ready) return null;
    final program = programs.program(id);
    return program == null
        ? Text(l10n.historyProgramDeleted)
        : InkWell(
            onTap: () => context.go(Routes.program(id)),
            child: Text(l10n.historyFromProgram(program.name)),
          );
  }
}

/// One set as logged: its kind, values, failure, effort and note, then its
/// drops.
class _SetLine extends StatelessWidget {
  const _SetLine({
    required this.exercise,
    required this.index,
    required this.set,
    required this.unit,
    required this.effort,
  });

  final WorkoutExercise exercise;
  final int index;
  final WorkoutSet set;
  final WeightUnit unit;
  final EffortScale effort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final type = exercise.loggingType;
    final number = exercise.sets
        .take(index + 1)
        .where((s) => !s.isWarmup)
        .length;
    final details = [
      l10n.setText(set, type, unit),
      if (set.toFailure) l10n.workoutFailureShort,
      if (set.rir case final rir?)
        l10n.effortText(rir, rpe: effort == EffortScale.rpe),
      ?set.note,
    ];
    return ListTile(
      dense: true,
      leading: Text(switch (set.type) {
        SetType.warmup => l10n.workoutWarmupShort,
        SetType.drop => '$number${l10n.workoutDropShort}',
        SetType.normal => '$number',
      }),
      title: Text(details.join(' · ')),
      subtitle: set.drops.isEmpty
          ? null
          : Text(
              [
                for (final (d, drop) in set.drops.indexed)
                  l10n.historyDropLine(
                    l10n.workoutDrop(d + 1),
                    l10n.setText(
                      WorkoutSet(weightKg: drop.weightKg, reps: drop.reps),
                      type,
                      unit,
                    ),
                  ),
              ].join('\n'),
            ),
    );
  }
}
