import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';
import 'widgets/set_table.dart';
import 'workout_detail_cubit.dart';
import 'workout_edit_page.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// A stored workout as it was logged: a header band with its totals, the
/// note, and each exercise's sets, opening and closing; ⋯ edits it (at
/// [routes], above this page) or deletes it once the server has its latest
/// change.
class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({super.key, required this.id, required this.routes});

  final String id;
  final WorkoutEditRoutes routes;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => sl<WorkoutDetailCubit>(param1: id)),
      BlocProvider.value(value: sl<ProgramListCubit>()),
    ],
    child: _DetailView(routes),
  );
}

class _DetailView extends StatelessWidget {
  const _DetailView(this.routes);
  final WorkoutEditRoutes routes;

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
          showForgeSnackbar(
            context,
            message: state.failure is NetworkFailure
                ? l10n.errorNetwork
                : l10n.historyDeleteFailed,
            error: true,
          );
          cubit.failureShown();
        }
      },
      builder: (context, state) {
        final workout = state.workout;
        return Scaffold(
          appBar: ForgeAppBar(
            title: l10n.historyDetailTitle,
            actions: [
              if (workout != null)
                Builder(
                  builder: (anchor) => ForgeAppBarAction.icon(
                    icon: ForgeIcons.moreHoriz,
                    label: l10n.historyOptions,
                    // Waiting to sync: it cannot change yet.
                    onPressed: state.canChange
                        ? () => showForgeMenu(
                            context: anchor,
                            items: [
                              ForgeMenuItem(
                                label: l10n.historyEdit,
                                icon: ForgeIcons.edit,
                                onTap: () => _edit(context, workout),
                              ),
                              ForgeMenuItem(
                                label: l10n.historyDelete,
                                icon: ForgeIcons.delete,
                                destructive: true,
                                onTap: () => _delete(context),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          ),
          body: switch (state.status) {
            WorkoutDetailStatus.missing => EmptyView(
              message: l10n.historyNotFound,
            ),
            WorkoutDetailStatus.failure when workout == null => ErrorView(
              title: l10n.historyLoadFailed,
              message: l10n.loadFailedDetail,
              retryLabel: l10n.retry,
              onRetry: cubit.retry,
            ),
            _ when workout == null => const _Loading(),
            _ => _Workout(state, workout),
          },
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Workout workout) async {
    // The edit page deletes it too, and says so.
    final deleted = await context.push<bool>(routes.edit(workout.id));
    if (deleted == true && context.mounted) context.pop();
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
      destructive: true,
    )) {
      await cubit.delete();
    }
  }
}

/// The band and two cards shimmering.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Gap.md),
    children: const [
      FeaturedCard.bandLoading(),
      SizedBox(height: Gap.md),
      ListRowCard(
        children: [
          ListRow.loading(),
          ListRow.loading(index: 1),
          ListRow.loading(index: 2),
        ],
      ),
      SizedBox(height: Gap.md),
      ListRowCard(children: [ListRow.loading(index: 1)]),
    ],
  );
}

class _Workout extends StatefulWidget {
  const _Workout(this.state, this.workout);
  final WorkoutDetailState state;
  final Workout workout;

  @override
  State<_Workout> createState() => _WorkoutState();
}

class _WorkoutState extends State<_Workout> {
  /// The exercises shown open; the first to begin with.
  final _open = <int>{0};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    final workout = widget.workout;
    final note = workout.note;
    return Column(
      children: [
        if (state.status == WorkoutDetailStatus.deleting)
          Progress.indeterminate(label: l10n.historyDeleting),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              _Header(workout: workout, records: state.records?.length),
              if (state.pending) ...[
                const SizedBox(height: Gap.md),
                NoticeBanner(
                  icon: ForgeIcons.cloudUpload,
                  title: l10n.historySyncingTitle,
                  message: l10n.historySyncingDetail,
                ),
              ],
              if (note != null) ...[
                const SizedBox(height: Gap.md),
                SectionCard.plain(title: l10n.historyNote, child: Text(note)),
              ],
              for (final (i, exercise) in workout.exercises.indexed) ...[
                const SizedBox(height: Gap.md),
                _ExerciseCard(
                  index: i,
                  exercise: exercise,
                  name: _name(context, exercise),
                  group: exercise.group == null
                      ? null
                      : groupItemLabel(workout.exercises, i),
                  records: state.records ?? const {},
                  open: _open.contains(i),
                  onToggle: () => setState(
                    () => _open.contains(i) ? _open.remove(i) : _open.add(i),
                  ),
                ),
              ],
            ],
          ),
        ),
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
}

/// The band: start, name and where it came from, over its four figures.
class _Header extends StatelessWidget {
  const _Header({required this.workout, required this.records});

  final Workout workout;

  /// Sets holding a record; null until known.
  final int? records;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final start = workout.startedAt;
    final summary = summarizeWorkout(workout);
    final (origin, onOrigin) = _origin(context, l10n);
    return FeaturedCard(
      form: FeaturedCardForm.band,
      eyebrow:
          '${l10n.planDate(CalendarDate.of(start))} · '
          '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
      title: workout.name,
      origin: origin,
      onOrigin: onOrigin,
      stats: [
        FeaturedStat(
          l10n.historyStatDuration,
          l10n.durationMinutes(summary.duration),
        ),
        FeaturedStat(
          l10n.historyStatVolume,
          summary.volumeKg > 0 ? l10n.weightText(summary.volumeKg, unit) : '—',
        ),
        FeaturedStat(l10n.historyStatSets, '${summary.setCount}'),
        FeaturedStat(l10n.historyStatRecords, '${records ?? '—'}'),
      ],
    );
  }

  /// The program it came from, with the week of the active copy's run it
  /// fell in, opening the program; once the programs are known.
  (String?, VoidCallback?) _origin(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final id = workout.programId;
    final programs = context.watch<ProgramListCubit>().state;
    if (id == null || programs.status != ProgramListStatus.ready) {
      return (null, null);
    }
    final program = programs.program(id);
    if (program == null) return (l10n.historyProgramDeleted, null);
    final active = programs.active;
    final week = active == null || active.programId != id
        ? null
        : ProgramSchedule(
            active,
            dayCount: program.days.length,
            lengthWeeks: program.lengthWeeks,
          ).runWeek(CalendarDate.of(workout.startedAt));
    return (
      week == null ? program.name : l10n.historyProgramWeek(program.name, week),
      () => context.go(Routes.program(id)),
    );
  }
}

/// An exercise as logged, as a [SetTable]: its group letter, name, logging
/// type (when not weight and reps), note and set count over a row per set,
/// each drop on its own row under its set; it opens and closes.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.index,
    required this.exercise,
    required this.name,
    required this.group,
    required this.records,
    required this.open,
    required this.onToggle,
  });

  final int index;
  final WorkoutExercise exercise;
  final String name;
  final String? group;
  final Set<(int, int)> records;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final unit = settings.weightUnit;
    final type = exercise.loggingType;
    return SetTable(
      name: name,
      group: group,
      type: type == LoggingType.weightReps ? null : l10n.loggingTypeName(type),
      note: exercise.note,
      count: l10n.historySetCount(exercise.sets.length),
      open: open,
      onToggle: onToggle,
      rows: [
        for (final (i, set) in exercise.sets.indexed)
          SetTableRow(
            label: l10n.setLabel(exercise, i),
            values: l10n.setWithUnitText(set, type, unit),
            effort: l10n.effortText(set, settings.effortScale),
            record: records.contains((index, i)),
            note: set.note,
            drops: [
              for (final drop in set.drops)
                l10n.setWithUnitText(
                  WorkoutSet(weightKg: drop.weightKg, reps: drop.reps),
                  type,
                  unit,
                ),
            ],
          ),
      ],
    );
  }
}
